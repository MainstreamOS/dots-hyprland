// Run with node --test. The pick Brightness.qml makes when the setting is Automatic.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const source = path.resolve(__dirname, '../../dots/.config/quickshell/ii/services/backlight-device.js');
const backlight = vm.createContext({});
vm.runInContext(fs.readFileSync(source, 'utf8').replace(/^\.pragma library\s*/, ''), backlight);
const pick = devices => backlight.automaticDevice(devices);

test('without a Touch Bar the choice stays with brightnessctl', () => {
    assert.equal(pick([]), '');
    assert.equal(pick(['intel_backlight']), '');
    assert.equal(pick(['acpi_video0', 'amdgpu_bl1']), '');
});

test('a Touch Bar listed first is never the pick', () => {
    assert.equal(pick(['appletb_backlight', 'intel_backlight']), 'intel_backlight');
    assert.equal(pick(['appletb_backlight', 'acpi_video0']), 'acpi_video0');
});

test('the gmux backlight wins when the kernel registered it', () => {
    assert.equal(pick(['appletb_backlight', 'acpi_video0', 'gmux_backlight']), 'gmux_backlight');
    assert.equal(pick(['acpi_video0', 'appletb_backlight', 'gmux_backlight', 'intel_backlight']), 'gmux_backlight');
});

test('a Touch Bar alone leaves the choice to brightnessctl', () => {
    assert.equal(pick(['appletb_backlight']), '');
});
