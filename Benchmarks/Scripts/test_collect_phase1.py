import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('collector', Path(__file__).with_name('collect-phase1.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class WatchdogTests(unittest.TestCase):
    def test_success_failure_and_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            limits = dict(module.DEFAULTS, trial=.2)
            collection = module.Collection(Path(directory)/'results', limits)
            try:
                collection.run('success', [sys.executable, '-c', 'print("ok")'], 'trial')
                with self.assertRaises(RuntimeError):
                    collection.run('failure', [sys.executable, '-c', 'exit(7)'], 'trial')
                with self.assertRaises(RuntimeError):
                    collection.run('timeout', [sys.executable, '-c',
                        'import subprocess,time; subprocess.Popen(["sleep", "60"]); time.sleep(60)'], 'trial')
                self.assertEqual([stage['status'] for stage in collection.stages], ['passed','failed','timed-out'])
                self.assertEqual(collection.stages[1]['exit_status'], 7)
                self.assertTrue(all(p.poll() is not None for p in collection.owned))
            finally:
                collection.cleanup()

    def test_invalid_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'invalid.perf'
            path.write_text('HTTP success is not a stack sample')
            with self.assertRaises(RuntimeError):
                module.validate(path)

if __name__ == '__main__':
    unittest.main()
