import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from fetch_toolchain import fetch


class CacheTests(unittest.TestCase):
    def test_offline_cache_is_verified_and_never_fetches(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent.parent / '_build') as directory:
            cache = Path(directory)
            spec = dict(name='test', sha256=hashlib.sha256(b'archive').hexdigest(), url='https://invalid.test')
            path = cache / ('test-' + spec['sha256'] + '.tar.gz')
            path.write_bytes(b'archive')
            with patch('fetch_toolchain.subprocess.run') as network:
                self.assertEqual(fetch(spec, cache), path)
                network.assert_not_called()
                path.write_bytes(b'corrupt')
                with self.assertRaisesRegex(ValueError, 'Corrupt'):
                    fetch(spec, cache)
                network.assert_not_called()

    def test_changed_download_is_not_promoted(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent.parent / '_build') as directory:
            cache = Path(directory)
            spec = dict(name='test', sha256=hashlib.sha256(b'expected').hexdigest(), url='https://invalid.test')
            def download(args, **kwargs):
                Path(args[-1]).write_bytes(b'changed')
            with patch('fetch_toolchain.subprocess.run', side_effect=download):
                with self.assertRaisesRegex(ValueError, 'Upstream archive changed'):
                    fetch(spec, cache)
            self.assertEqual(list(cache.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
