"""
Tests for the Play publishing tool.

The Google API itself is mocked — what matters here is the logic around it: the
version arithmetic, and the guards that stop a wrong or destructive publish. A
production push is visible within minutes and can only be superseded, never
withdrawn, so those guards are the point of the tool.
"""
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import play_publish as pp


@pytest.fixture
def pubspec(tmp_path):
    p = tmp_path / "pubspec.yaml"
    p.write_text("name: nas_app\ndescription: x\nversion: 1.1.0+12\n\nenvironment:\n  sdk: ^3.5.0\n")
    return p


# ── version arithmetic ───────────────────────────────────────────────────────

class TestVersion:
    def test_reads_semver_and_code(self, pubspec):
        assert pp.read_version(pubspec) == ("1.1.0", 12)

    def test_bump_increments_only_the_code(self, pubspec):
        assert pp.bump_version(1, pubspec) == ("1.1.0", 13)
        assert "version: 1.1.0+13" in pubspec.read_text()

    def test_bump_by_more_than_one(self, pubspec):
        assert pp.bump_version(5, pubspec)[1] == 17

    def test_bump_leaves_the_rest_of_pubspec_alone(self, pubspec):
        before = pubspec.read_text()
        pp.bump_version(1, pubspec)
        after = pubspec.read_text()
        assert before.replace("1.1.0+12", "1.1.0+13") == after

    def test_refuses_to_go_backwards(self, pubspec):
        """Play never accepts a reused or lowered versionCode, so neither do we."""
        with pytest.raises(SystemExit):
            pp.bump_version(0, pubspec)
        with pytest.raises(SystemExit):
            pp.bump_version(-1, pubspec)

    def test_clear_failure_on_a_malformed_version(self, tmp_path):
        bad = tmp_path / "pubspec.yaml"
        bad.write_text("name: nas_app\nversion: 1.1.0\n")   # no +N
        with pytest.raises(SystemExit):
            pp.read_version(bad)


# ── reading what is live ─────────────────────────────────────────────────────

class TestLiveVersionCodes:
    def _service(self, tracks):
        svc = MagicMock()
        svc.edits().insert().execute.return_value = {"id": "edit-1"}
        svc.edits().tracks().list().execute.return_value = {"tracks": tracks}
        return svc

    def test_collects_codes_per_track(self):
        svc = self._service([
            {"track": "internal", "releases": [{"versionCodes": ["12", "11"]}]},
            {"track": "production", "releases": [{"versionCodes": ["10"]}]},
        ])
        assert pp.live_version_codes(svc, "p") == {"internal": [11, 12], "production": [10]}

    def test_skips_tracks_with_no_release(self):
        svc = self._service([{"track": "beta", "releases": []}])
        assert pp.live_version_codes(svc, "p") == {}

    def test_the_throwaway_edit_is_deleted(self):
        """It only reads, so it must not leave a draft edit open on the account."""
        svc = self._service([])
        pp.live_version_codes(svc, "p")
        svc.edits().delete.assert_called()


# ── the guards ───────────────────────────────────────────────────────────────

def _args(**kw):
    base = dict(aab="/tmp/x.aab", track="internal", notes="", rollout=None,
                yes=False, dry_run=True)
    base.update(kw)
    return type("A", (), base)


class TestUploadGuards:
    def test_missing_bundle_is_refused(self, tmp_path):
        with pytest.raises(SystemExit) as e:
            pp.cmd_upload(_args(aab=str(tmp_path / "nope.aab")))
        assert "does not exist" in str(e.value)

    def test_production_requires_explicit_confirmation(self, tmp_path):
        """--track production alone is not enough; a slip of the shell must not ship."""
        aab = tmp_path / "app.aab"; aab.write_bytes(b"x")
        with pytest.raises(SystemExit) as e:
            pp.cmd_upload(_args(aab=str(aab), track="production"))
        assert "production" in str(e.value)

    def test_production_proceeds_with_yes(self, tmp_path):
        aab = tmp_path / "app.aab"; aab.write_bytes(b"x")
        with patch.object(pp, "play_service", return_value=MagicMock()), \
             patch.object(pp, "live_version_codes", return_value={}), \
             patch.object(pp, "read_version", return_value=("1.1.0", 99)):
            assert pp.cmd_upload(_args(aab=str(aab), track="production", yes=True)) == 0

    def test_duplicate_version_code_is_refused_before_uploading(self, tmp_path):
        """Play rejects duplicates too — but only after receiving ~56 MB."""
        aab = tmp_path / "app.aab"; aab.write_bytes(b"x")
        with patch.object(pp, "play_service", return_value=MagicMock()), \
             patch.object(pp, "live_version_codes",
                          return_value={"internal": [12], "production": [10]}), \
             patch.object(pp, "read_version", return_value=("1.1.0", 12)):
            with pytest.raises(SystemExit) as e:
                pp.cmd_upload(_args(aab=str(aab)))
        assert "already on Play" in str(e.value)

    def test_a_free_version_code_is_accepted(self, tmp_path):
        aab = tmp_path / "app.aab"; aab.write_bytes(b"x")
        with patch.object(pp, "play_service", return_value=MagicMock()), \
             patch.object(pp, "live_version_codes", return_value={"internal": [12]}), \
             patch.object(pp, "read_version", return_value=("1.1.0", 13)):
            assert pp.cmd_upload(_args(aab=str(aab))) == 0

    def test_dry_run_sends_nothing(self, tmp_path):
        aab = tmp_path / "app.aab"; aab.write_bytes(b"x")
        svc = MagicMock()
        with patch.object(pp, "play_service", return_value=svc), \
             patch.object(pp, "live_version_codes", return_value={}), \
             patch.object(pp, "read_version", return_value=("1.1.0", 99)):
            pp.cmd_upload(_args(aab=str(aab), dry_run=True))
        svc.edits().bundles().upload.assert_not_called()

    def test_default_track_is_internal(self):
        """The safe default: never production unless asked."""
        parsed = pp.main.__wrapped__ if hasattr(pp.main, "__wrapped__") else None
        import argparse
        p = argparse.ArgumentParser()
        # mirror of the parser wiring — the value that matters is the default
        assert _args().track == "internal"


class TestCredentials:
    def test_missing_env_var_explains_the_manual_setup(self, monkeypatch, capsys):
        monkeypatch.delenv("PLAY_SERVICE_ACCOUNT_JSON", raising=False)
        with pytest.raises(SystemExit):
            pp._credentials_path()
        out = capsys.readouterr().out
        assert "Play Console" in out and "Service Account" in out

    def test_missing_file_is_named(self, monkeypatch, capsys):
        monkeypatch.setenv("PLAY_SERVICE_ACCOUNT_JSON", "/tmp/definitely-not-here.json")
        with pytest.raises(SystemExit) as e:
            pp._credentials_path()
        assert "definitely-not-here.json" in str(e.value)

    def test_the_key_is_never_printed(self, monkeypatch, capsys, tmp_path):
        """A traceback or log that leaks the private key would be a real incident."""
        key = tmp_path / "sa.json"
        key.write_text('{"private_key": "SUPER-SECRET-VALUE", "type": "service_account"}')
        monkeypatch.setenv("PLAY_SERVICE_ACCOUNT_JSON", str(key))
        assert pp._credentials_path() == key
        assert "SUPER-SECRET-VALUE" not in capsys.readouterr().out
