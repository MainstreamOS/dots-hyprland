pragma Singleton
import Quickshell

Singleton {
    id: root

    function intersectionOverUnion(regionA, regionB) {
        // region: { at: [x, y], size: [w, h] }
        const ax1 = regionA.at[0], ay1 = regionA.at[1];
        const ax2 = ax1 + regionA.size[0], ay2 = ay1 + regionA.size[1];
        const bx1 = regionB.at[0], by1 = regionB.at[1];
        const bx2 = bx1 + regionB.size[0], by2 = by1 + regionB.size[1];

        const interX1 = Math.max(ax1, bx1);
        const interY1 = Math.max(ay1, by1);
        const interX2 = Math.min(ax2, bx2);
        const interY2 = Math.min(ay2, by2);

        const interArea = Math.max(0, interX2 - interX1) * Math.max(0, interY2 - interY1);
        const areaA = (ax2 - ax1) * (ay2 - ay1);
        const areaB = (bx2 - bx1) * (by2 - by1);
        const unionArea = areaA + areaB - interArea;

        return unionArea > 0 ? interArea / unionArea : 0;
    }

    function filterOverlappingImageRegions(regions) {
        let keep = [];
        let removed = new Set();
        for (let i = 0; i < regions.length; ++i) {
            if (removed.has(i)) continue;
            let regionA = regions[i];
            for (let j = i + 1; j < regions.length; ++j) {
                if (removed.has(j)) continue;
                let regionB = regions[j];
                if (intersectionOverUnion(regionA, regionB) > 0) {
                    // Compare areas
                    let areaA = regionA.size[0] * regionA.size[1];
                    let areaB = regionB.size[0] * regionB.size[1];
                    if (areaA <= areaB) {
                        removed.add(j);
                    } else {
                        removed.add(i);
                    }
                }
            }
        }
        for (let i = 0; i < regions.length; ++i) {
            if (!removed.has(i)) keep.push(regions[i]);
        }
        return keep;
    }

    // How much of `inner` the region `outer` covers, from 0 to 1.
    function coveredFraction(inner, outer) {
        const interX = Math.max(0, Math.min(inner.at[0] + inner.size[0], outer.at[0] + outer.size[0]) - Math.max(inner.at[0], outer.at[0]));
        const interY = Math.max(0, Math.min(inner.at[1] + inner.size[1], outer.at[1] + outer.size[1]) - Math.max(inner.at[1], outer.at[1]));
        const innerArea = inner.size[0] * inner.size[1];
        return innerArea > 0 ? (interX * interY) / innerArea : 0;
    }

    // A layer's surface often reaches past what it draws, like a sidebar
    // sized for its extended width, so touching a window is no sign of
    // hiding it. Only a window a layer covers almost entirely is out of reach.
    function filterWindowRegionsByLayers(windowRegions, layerRegions, hiddenFraction = 0.9) {
        return windowRegions.filter(windowRegion => {
            return !layerRegions.some(layerRegion => coveredFraction(windowRegion, layerRegion) >= hiddenFraction);
        });
    }

    function filterImageRegions(regions, windowRegions, threshold = 0.1) {
        // Remove image regions that overlap too much with any window region
        let filtered = regions.filter(region => {
            for (let i = 0; i < windowRegions.length; ++i) {
                if (intersectionOverUnion(region, windowRegions[i]) > threshold)
                    return false;
            }
            return true;
        });
        // Remove overlapping image regions, keep only the smaller one
        return filterOverlappingImageRegions(filtered);
    }
}
