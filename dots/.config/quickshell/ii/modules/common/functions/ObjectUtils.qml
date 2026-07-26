pragma Singleton
import Quickshell

Singleton {
    id: root

    // One group of a model-driven bar layout, read as { id, enabled } entries.
    // Tolerant of the legacy string / items group forms.
    function layoutGroupWidgets(g) {
        if (!g) return [];
        if (typeof g === "string") return [{ id: g, enabled: true }];
        const entries = (g.widgets !== undefined) ? g.widgets
            : (g.items !== undefined) ? g.items
            : [];
        return Array.prototype.slice.call(entries)
            .map(w => (typeof w === "string") ? ({ id: w, enabled: true }) : w)
            .filter(w => w);
    }

    // Whether a widget id is present and enabled in a model-driven bar layout
    // ({ left, center, right } lists of { widgets: [{ id, enabled }] } groups).
    function layoutHasEnabledWidget(layout, id) {
        return root.layoutFindWidget(layout, id, w => w.enabled);
    }

    // Whether a widget id appears at all, however it is spelled and whether or
    // not it is switched on.
    function layoutHasWidget(layout, id) {
        return root.layoutFindWidget(layout, id, () => true);
    }

    function layoutFindWidget(layout, id, accept) {
        if (!layout) return false;
        const sections = [layout.left, layout.center, layout.right];
        for (let s = 0; s < sections.length; s++) {
            if (!sections[s]) continue;
            const groups = Array.prototype.slice.call(sections[s]);
            for (let i = 0; i < groups.length; i++) {
                const widgets = root.layoutGroupWidgets(groups[i]);
                for (let j = 0; j < widgets.length; j++)
                    if (widgets[j].id === id && accept(widgets[j])) return true;
            }
        }
        return false;
    }

    function toPlainObject(qtObj) {
        if (qtObj === null || typeof qtObj !== "object") return qtObj;

        // Handle true arrays
        if (Array.isArray(qtObj)) {
            return qtObj.map(item => toPlainObject(item));
        }

        // Handle array-like Qt objects (e.g., have length and numeric keys)
        if (
            typeof qtObj.length === "number" &&
            qtObj.length > 0 &&
            Object.keys(qtObj).every(
                key => !isNaN(key) || key === "length"
            )
        ) {
            let arr = [];
            for (let i = 0; i < qtObj.length; i++) {
                arr.push(toPlainObject(qtObj[i]));
            }
            return arr;
        }

        const result = ({});
        for (let key in qtObj) {
            if (
                typeof qtObj[key] !== "function" &&
                !key.startsWith("objectName") &&
                !key.startsWith("children") &&
                !key.startsWith("object") &&
                !key.startsWith("parent") &&
                !key.startsWith("metaObject") &&
                !key.startsWith("destroyed") &&
                !key.startsWith("reloadableId")
            ) {
                result[key] = toPlainObject(qtObj[key]);
            }
        }
        // console.log(JSON.stringify(result))
        return result;
    }

    function applyToQtObject(qtObj, jsonObj) {
        // console.log("applyToQtObject", JSON.stringify(qtObj, null, 2), "<<", JSON.stringify(jsonObj, null, 2));
        if (!qtObj || typeof jsonObj !== "object" || jsonObj === null) return;

        // Detect array-like Qt objects
        const isQtArrayLike = obj => {
            return obj && typeof obj === "object" &&
                typeof obj.length === "number" &&
                obj.length > 0 &&
                Object.keys(obj).every(key => !isNaN(key) || key === "length");
        };

        // If both are arrays or array-like, update in place or replace
        if ((Array.isArray(qtObj) || isQtArrayLike(qtObj)) && Array.isArray(jsonObj)) {
            qtObj.length = 0;
            for (let i = 0; i < jsonObj.length; i++) {
                qtObj.push(jsonObj[i]);
            }
            return;
        }

        // If target is array or array-like but source is not, clear
        if ((Array.isArray(qtObj) || isQtArrayLike(qtObj)) && !Array.isArray(jsonObj)) {
            qtObj.length = 0;
            return;
        }

        // If source is array but target is not, assign directly if possible
        if (!(Array.isArray(qtObj) || isQtArrayLike(qtObj)) && Array.isArray(jsonObj)) {
            return jsonObj;
        }

        for (let key in jsonObj) {
            if (!qtObj.hasOwnProperty(key)) continue;
            const value = qtObj[key];
            const jsonValue = jsonObj[key];
            // console.log("applying to qt obj key:", value, "jsonValue:", jsonValue);
            if ((Array.isArray(value) || isQtArrayLike(value)) && Array.isArray(jsonValue)) {
                value.length = 0;
                for (let i = 0; i < jsonValue.length; i++) {
                    value.push(jsonValue[i]);
                }
            } else if (value && typeof value === "object" && !Array.isArray(value) && !isQtArrayLike(value)) {
                applyToQtObject(value, jsonValue);
            } else {
                qtObj[key] = jsonValue;
            }
        }
    }
}
