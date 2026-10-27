import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

path = Path(__file__).with_name('session-runtime-lifecycle.test.py')
spec = importlib.util.spec_from_file_location('session_runtime_lifecycle', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RuntimeAPIBackpressureTests(unittest.TestCase):
    def api(self):
        api = module.RuntimeAPI.__new__(module.RuntimeAPI)
        api.backpressure_counts = {}
        api.observe = Mock()
        return api

    def test_post_retries_the_same_operation_after_busy(self):
        api = self.api()
        operation = {'id': 'original', 'payload': 'value'}
        api.request_once = Mock(side_effect=[(503, {}), (200, {'accepted': True})])
        with patch.object(module.time, 'sleep'):
            result = api.request('POST', '/command', operation)
        self.assertEqual(result, (200, {'accepted': True}))
        self.assertEqual(api.backpressure_counts, {'POST /command': 1})
        self.assertEqual(api.request_once.call_count, 2)
        self.assertIs(api.request_once.call_args_list[0].args[2], operation)
        self.assertIs(api.request_once.call_args_list[1].args[2], operation)

    def test_post_reports_busy_after_deadline(self):
        api = self.api()
        api.request_once = Mock(return_value=(503, {}))
        with patch.object(module.time, 'monotonic', side_effect=[0, 5]):
            with self.assertRaisesRegex(AssertionError, 'HTTP 503'):
                api.request('POST', '/command', {'id': 'original'})
        self.assertEqual(api.request_once.call_count, 1)


if __name__ == '__main__':
    unittest.main()
