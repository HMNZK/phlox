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


class AXWindowObservationTests(unittest.TestCase):
    def setUp(self):
        self.identity = module.process_info(module.os.getpid())[0]

    def test_recycled_wrapper_address_does_not_hide_a_later_sibling_label(self):
        framework = RecycledAXFramework()
        with framework.installed():
            result = module.accessibility_window_state(self.identity, 'runtime-target')

        self.assertTrue(result['expectedTextPresent'])
        self.assertIn('runtime-target', result['visibleTexts'])
        self.assertEqual(framework.live_objects, 0)

    def test_unmatched_scan_releases_all_elements(self):
        framework = RecycledAXFramework()
        with framework.installed():
            result = module.accessibility_window_state(self.identity, 'absent-session')

        self.assertFalse(result['expectedTextPresent'])
        self.assertEqual(framework.live_objects, 0)

    def test_failed_attribute_read_releases_all_elements(self):
        framework = RecycledAXFramework(fail_on_target=True)
        with framework.installed():
            with self.assertRaisesRegex(RuntimeError, 'AX read failed'):
                module.accessibility_window_state(self.identity, 'runtime-target')

        self.assertEqual(framework.live_objects, 0)


class RecycledAXFramework:
    def __init__(self, fail_on_target=False):
        self.objects = {}
        self.recycled_nodes = []
        self.next_node = 1000
        self.next_value = 100000
        self.fail_on_target = fail_on_target
        self.AXUIElementCreateApplication = lambda pid: self.allocate('node', 'app')
        self.AXUIElementSetMessagingTimeout = lambda app, duration: 0
        self.AXUIElementCopyAttributeValue = self.copy_attribute
        self.CFStringCreateWithCString = lambda allocator, text, encoding: self.allocate('string', text.decode())
        self.CFArrayGetCount = lambda value: len(self.get(value)['value'])
        self.CFArrayGetValueAtIndex = lambda value, index: self.get(value)['value'][index]
        self.CFGetTypeID = lambda value: {'string': 1, 'array': 2, 'node': 3}[self.get(value)['kind']]
        self.CFStringGetTypeID = lambda: 1
        self.CFArrayGetTypeID = lambda: 2
        self.CFStringGetCString = self.copy_string
        self.CFRetain = self.retain
        self.CFRelease = self.release
        for name in ('AXUIElementCopyAttributeValue', 'CFStringGetCString', 'CFRetain', 'CFRelease'):
            function = getattr(self, name)
            setattr(self, name, lambda *args, call=function: call(*args))

    @property
    def live_objects(self):
        return len(self.objects)

    def installed(self):
        original = module.ctypes.CDLL

        def load(name, *args, **kwargs):
            if name.endswith(('/ApplicationServices', '/CoreFoundation')):
                return self
            return original(name, *args, **kwargs)

        return patch.object(module.ctypes, 'CDLL', side_effect=load)

    def allocate(self, kind, value):
        if kind == 'node':
            if self.recycled_nodes:
                address = self.recycled_nodes.pop()
            else:
                address = self.next_node
                self.next_node += 1
        else:
            address = self.next_value
            self.next_value += 1
        self.objects[address] = dict(kind=kind, value=value, references=1)
        return address

    def address(self, value):
        return value.value if isinstance(value, module.ctypes.c_void_p) else value

    def get(self, value):
        return self.objects[self.address(value)]

    def retain(self, value):
        self.get(value)['references'] += 1
        return self.address(value)

    def release(self, value):
        address = self.address(value)
        entry = self.objects[address]
        entry['references'] -= 1
        if entry['references']:
            return
        del self.objects[address]
        if entry['kind'] == 'array':
            for child in entry['value']:
                self.release(child)
        elif entry['kind'] == 'node':
            self.recycled_nodes.append(address)

    def copy_attribute(self, element, attribute, output):
        node = self.get(element)['value']
        name = self.get(attribute)['value']
        children = {('app', 'AXWindows'): ['window'], ('window', 'AXChildren'): ['left', 'right'],
                    ('left', 'AXChildren'): ['left-label'], ('right', 'AXChildren'): ['right-label']}
        labels = {'left-label': 'unrelated-label', 'right-label': 'runtime-target'}
        if (node, name) in children:
            value = self.allocate('array', [self.allocate('node', child) for child in children[node, name]])
        elif name == 'AXTitle' and node in labels:
            value = self.allocate('string', labels[node])
        else:
            return -25205
        module.ctypes.cast(output, module.ctypes.POINTER(module.ctypes.c_void_p))[0] = value
        return 0

    def copy_string(self, value, buffer, size, encoding):
        text = self.get(value)['value']
        if self.fail_on_target and text == 'runtime-target':
            raise RuntimeError('AX read failed')
        buffer.value = text.encode()
        return True


if __name__ == '__main__':
    unittest.main()
