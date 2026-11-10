#!/usr/bin/env python3
"""Exercise shipped workspace selectors and generated drop commands with 0.57 data.
Requires Lua and Node; does not contact the compositor or change the desktop.
"""
import ast
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / 'dots/.config'

def run(command, text):
    return subprocess.run(command, input=text, text=True, capture_output=True, check=True).stdout

def lua(source):
    return run(['lua', '-'], f'package.path = "{CONFIG}/hypr/?.lua;" .. package.path\n' + source)

class WorkspaceTests(unittest.TestCase):
    def test_lua_identity_and_restore(self):
        plugin = (CONFIG / 'hypr/hyprland/plugins.lua').read_text()
        titlebar = plugin[plugin.index('local Workspace ='):plugin.index('-- The maximize button')]
        lua('''
local Workspace = require('hyprland.workspace')
local cases = {
    {{id=2, name='Entertainment', addressable_name='2'}, '2'},
    {{name='Coding', addressable_name='dev'}, 'name:dev'},
    {{name='Numeric name', addressable_name='2',special=false}, 'name:2'},
    {{name='Minimized', addressable_name='special:special', special=true}, 'special'},
    {{name='Other', addressable_name='special:other', special=true}, 'special:other'},
    {{id=-99, name='special:special', special=true}, 'special'},
    {{id=-4, name='Legacy'}, 'name:Legacy'},
}
for _, case in ipairs(cases) do assert(Workspace.selector(case[1]) == case[2]) end
assert(not Workspace.same({addressable_name='one'}, {addressable_name='two'}))
assert(not Workspace.same(nil, nil))
local current, target
hl = {get_active_window=function() return current end,
      get_active_monitor=function() return {active_workspace=target} end,
      timer=function() end,
      dsp={window={move=function(t) return t end, fullscreen=function(t) return t end},
           no_op=function() return {noop=true} end}}
''' + titlebar + '''
current={workspace={special=true,addressable_name='special:special'}}
target={name='Coding',addressable_name='dev'}
assert(MainstreamTitleBarStep('up').workspace == 'name:dev')
assert(MainstreamTitleBarStep('down').noop)
current.workspace={special=true,addressable_name='special:other'}
assert(MainstreamTitleBarStep('down').workspace == 'special')
''')

    def test_drop_restores_distinct_named_workspace(self):
        source = (CONFIG / 'quickshell/ii/modules/ii/overview/placement.js').read_text().replace('.pragma library', '')
        generated = run(['node', '-'], source + "\nconsole.log(script('drag','special:one','anchor','r',0,0));")
        lua('''
local a = {addressable_name='special:one',name='Same label'}
local b = {addressable_name='special:two',name='Same label'}
local w={address='drag',workspace=a,mapped=true,monitor={id=0}}
local previous={address='previous',workspace=b,mapped=true}
local anchor={address='anchor',workspace=b,mapped=true}
local active=previous
local restored=false
hl={get_window=function(s) if s=='address:drag' then return w else return anchor end end,
    get_active_window=function() return active end,
    get_active_workspace=function() return b end,
    get_cursor_pos=function() return nil end,
    dsp={focus=function(t) return t end,window={move=function(t) return t end,
         swap=function() error('Must not place against an anchor on another workspace') end}},
    dispatch=function(t)
      if t.window=='address:drag' then active=w end
      if t.window=='address:previous' then active=previous end
      if t.workspace=='special:two' then restored=true end
    end}
''' + generated + '''
assert(restored and active==previous, 'Distinct nonnumeric workspaces must not compare equal')
''')

    def test_session_addresses(self):
        path = CONFIG / 'quickshell/ii/scripts/session/session.py'
        fn = next(n for n in ast.parse(path.read_text()).body if isinstance(n, ast.FunctionDef) and n.name == 'workspace_selector')
        scope = {}
        exec(compile(ast.Module(body=[fn], type_ignores=[]), str(path), 'exec'), scope)
        selector = scope['workspace_selector']
        for workspace, expected in [
            ({'address':'dev','name':'Coding','type':'normal'}, 'name:dev'),
            ({'address':'2','id':2,'name':'Entertainment'}, '2'),
            ({'address':'special:special','name':'Minimized','type':'special'}, 'special'),
            ({'id':-99,'name':'special:special'}, 'special'),
            ({'id':-2,'name':'Legacy'}, 'name:Legacy'),
        ]:
            self.assertEqual(selector(workspace), expected)

    def test_special_workspace_guards(self):
        source = (CONFIG / 'quickshell/ii/services/HyprlandData.qml').read_text()
        fn = source[source.index('    function isSpecialWorkspace('):source.index('    function toplevelsForWorkspace(')]
        run(['node','-'], fn + '''
const assert=require('node:assert/strict');
assert.equal(isSpecialWorkspace({address:'special:special',type:'special'}),true);
assert.equal(isSpecialWorkspace({id:-99,name:'special:special'}),true);
assert.equal(isSpecialWorkspace({id:1,type:'normal',name:'special:renamed'}),false);
assert.equal(isSpecialWorkspace({address:'',id:0,name:''}),false);
assert.equal(isSpecialWorkspace(null),false);
''')

    def test_launcher_geometry_stays_in_place_in_fullscreen(self):
        source = (CONFIG / 'quickshell/ii/modules/ii/overview/launcher-layout.js').read_text().replace('.pragma library', '')
        run(['node', '-'], source + """
const assert = require('node:assert/strict');
function close(a, b) { assert.ok(Math.abs(a - b) < 0.00001, [a, b]); }
for (const edge of [1, 3]) {
    for (const scale of [1, 1.5, 2]) {
        const reserved = [0, 0, 0, 0];
        reserved[edge] = 60;
        const normal = {
            monitor: { width: 2560 * scale, height: 1440 * scale, scale, transform: 0 },
            reserved, rows: 2, columns: 5, size: 100, unit: 1, elevation: 10
        };
        const full = { ...normal, reserved: [0, 0, 0, 0], layoutReserved: reserved };
        const a = workspaceGrid(normal), b = workspaceGrid(full);
        for (const key of ['cellWidth', 'cellHeight', 'bodyHeight']) close(a[key], b[key]);
        assert.deepEqual(b.reserved, [0, 0, 0, 0]);
        assert.ok(1440 * b.previewScale <= b.cellHeight + 0.00001);
        for (const swapped of [false, true]) {
            const options = {
                unit: 1, width: 2400, height: 1200, screenWidth: 2560, screenHeight: 1440,
                centerX: 1200, centerY: 600, searchHeight: 80, count: 3, shown: 3,
                swapped, recentApps: true
            };
            const windowed = scrolling({ ...options, reserved });
            const fullscreen = scrolling({ ...options, reserved: full.reserved, layoutReserved: reserved });
            for (const key of ['totalWidth', 'panelHeight', 'slotHeight', 'drawerHeight'])
                close(windowed[key], fullscreen[key]);
            for (const panel of ['workspace', 'apps']) {
                for (const key of ['x', 'y', 'width', 'height'])
                    close(windowed[panel][key], fullscreen[panel][key]);
            }
            close(fullscreen.previewWidth * 1440 / 2560, fullscreen.slotHeight);
        }
    }
}
""")

    def test_fullscreen_membership_uses_addresses(self):
        source = (CONFIG / 'quickshell/ii/services/HyprlandData.qml').read_text()
        functions = source[source.index('    function isSpecialWorkspace('):source.index('    function toplevelsForWorkspace(')]
        run(['node','-'], functions + '''
const assert=require('node:assert/strict');
const window={monitor:0,workspace:{address:'dev',name:'Coding',type:'normal'}};
const monitor={id:0,name:'DP-1',activeWorkspace:{address:'dev',name:'Renamed',type:'normal'},specialWorkspace:{id:0}};
const ToplevelManager={toplevels:{values:[{fullscreen:true}]}};
const root={monitors:[monitor],clientForToplevel:()=>window,isSpecialWorkspace,workspaceAddress};
assert.equal(activeWorkspaceHasFullscreen('DP-1'),true);
assert.equal(activeWorkspaceHasFullscreen('DP-2'),false);
window.workspace={address:'design',name:'Coding',type:'normal'};
assert.equal(activeWorkspaceHasFullscreen(),false);
monitor.specialWorkspace={address:'special:special',name:'Minimized',type:'special'};
window.workspace={address:'special:special',type:'special'};
assert.equal(activeWorkspaceHasFullscreen('DP-1'),true);
ToplevelManager.toplevels.values[0].fullscreen=false;
assert.equal(activeWorkspaceHasFullscreen('DP-1'),false);
''')

if __name__ == '__main__': unittest.main()
