"""Deployment checks use a temporary fake game; never touch installed files."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import deploy


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.game = self.root / 'game'
        for folder in ('build', 'releases', 'game/bin', 'game/data/game'):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        (self.game / 'bin/helldivers2.exe').write_bytes(b'changed exe')
        (self.game / 'data/game/game.dll').write_bytes(b'changed dll')
        self.existing = self.game / 'data' / (deploy.ARCHIVE + '.patch_0')
        self.existing.write_bytes(b'unrelated mod')
        self.package = self.root / 'releases/Rover-Fire-Spread-Experimental-0.4.1.zip'
        with zipfile.ZipFile(self.package, 'w') as archive:
            for suffix in ('', '.stream', '.gpu_resources'):
                archive.writestr('data/' + deploy.ARCHIVE + '.patch_0' + suffix, b'new' if not suffix else b'')
        (self.root / 'build/experimental-package-report.json').write_text(json.dumps({
            'zip_name': self.package.name, 'zip_sha256': deploy.sha(self.package.read_bytes())}))
        self.journal = self.root / 'build/deployment.json'

    def install(self, closed_error=None, variant='hud', action='install'):
        with patch.object(deploy, 'ROOT', self.root), patch.object(deploy, 'GAME', self.game), \
                patch.object(deploy, 'JOURNAL', self.journal), \
                patch.object(deploy, 'require_closed', side_effect=closed_error), \
                patch.object(sys, 'argv', ['deploy.py', action, '--variant', variant]), contextlib.redirect_stdout(io.StringIO()) as output:
            deploy.main()
        return output.getvalue()

    def test_changed_game_hashes_allow_install_and_are_recorded(self):
        self.assertIn('WARNING: unverified game file', self.install())
        record = json.loads(self.journal.read_text())
        self.assertEqual(record['compatibility'], 'unverified_build_attempt')
        self.assertEqual(record['status'], 'installed')
        self.assertEqual(record['game_hashes']['bin/helldivers2.exe'], deploy.sha(b'changed exe'))
        self.assertEqual(self.existing.read_bytes(), b'unrelated mod')
        self.assertEqual((self.game / 'data' / (deploy.ARCHIVE + '.patch_1')).read_bytes(), b'new')

    def test_package_integrity_still_blocks_install(self):
        self.package.write_bytes(self.package.read_bytes() + b'changed')
        with self.assertRaisesRegex(ValueError, 'Package checksum mismatch'):
            self.install()
        self.assertFalse(self.journal.exists())
        self.assertEqual(list((self.game / 'data').glob('*.patch_*')), [self.existing])

    def test_running_game_still_blocks_install(self):
        with self.assertRaisesRegex(RuntimeError, 'running'):
            self.install(RuntimeError('Game running'))
        self.assertFalse(self.journal.exists())

    def no_hud_report(self, enabled=False):
        target=self.package.with_name('激光狗索敌优化-0.7.2-v12-内置加载器-No-HUD.zip')
        target.write_bytes(self.package.read_bytes())
        (self.root/'build/experimental-package-report-no-hud.json').write_text(json.dumps({
            'zip_name':target.name,'zip_sha256':deploy.sha(target.read_bytes()),'hud':{'enabled':enabled}}))

    def test_no_hud_install_and_switch_require_uninstall_preserving_other_mods(self):
        self.no_hud_report();self.install(variant='no-hud')
        self.assertEqual(json.loads(self.journal.read_text())['variant'],'no-hud')
        with self.assertRaisesRegex(RuntimeError,'prior installation'):
            self.install()
        self.install(action='uninstall')
        self.install()
        self.assertEqual(json.loads(self.journal.read_text())['variant'],'hud')
        self.assertEqual(self.existing.read_bytes(),b'unrelated mod')

    def test_no_hud_report_rejects_a_hud_enabled_package(self):
        self.no_hud_report(enabled=True)
        with self.assertRaisesRegex(ValueError,'explicitly disable HUD'):
            self.install(variant='no-hud')
        self.assertFalse(self.journal.exists())


if __name__ == '__main__':
    unittest.main()
