pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Renders LaTeX snippets with MicroTeX.
 * For every request:
 *   1. Hash it
 *   2. Check if the hash is already processed
 *   3. If not, queue it for MicroTeX and mark as processed
 */
Singleton {
    id: root

    readonly property var renderPadding: 4 // This is to prevent cutoff in the rendered images
    readonly property int maxRunning: 3

    property var processedHashes: ({})
    property var processedExpressions: ({})
    property var renderedImagePaths: ({})
    property string microtexBinaryDir: "/opt/MicroTeX"
    property string microtexBinaryName: "LaTeX"
    property string latexOutputPath: Directories.latexOutput

    property var _queue: []
    property int _running: 0

    signal renderFinished(string hash, string imagePath)

    /**
    * Requests rendering of a LaTeX expression.
    * Returns the [hash, isNew]
    */
    function requestRender(expression) {
        const hash = Qt.md5(expression)
        const imagePath = `${latexOutputPath}/${hash}.svg`

        if (root.processedHashes[hash]) {
            // Queued or running renders report when they finish.
            if (root.renderedImagePaths[hash]) root.renderFinished(hash, imagePath)
            return [hash, false]
        }
        root.processedHashes[hash] = true
        root.processedExpressions[hash] = expression
        root._queue.push({ hash: hash, expression: expression, imagePath: imagePath })
        root._startNext()
        return [hash, true]
    }

    function _startNext(): void {
        while (root._running < root.maxRunning && root._queue.length > 0) {
            const job = root._queue.shift()
            root._running++
            renderProcess.createObject(root, {
                hash: job.hash,
                imagePath: job.imagePath,
                command: [
                    `${root.microtexBinaryDir}/${root.microtexBinaryName}`,
                    "-headless",
                    `-input=${job.expression}`,
                    `-output=${job.imagePath}`,
                    `-textsize=${Appearance.font.pixelSize.normal}`,
                    `-padding=${root.renderPadding}`,
                    `-foreground=${Appearance.colors.colOnLayer1}`,
                    "-maxwidth=0.85"
                ],
                workingDirectory: root.microtexBinaryDir,
                running: true
            })
        }
    }

    Component {
        id: renderProcess
        Process {
            id: proc
            property string hash
            property string imagePath
            property bool started: false
            property bool finished: false

            function finish(success: bool): void {
                if (proc.finished) return
                proc.finished = true
                root._running--
                if (success) {
                    root.renderedImagePaths[proc.hash] = proc.imagePath
                    root.renderFinished(proc.hash, proc.imagePath)
                }
                root._startNext()
                proc.destroy()
            }

            onStarted: proc.started = true
            onExited: (exitCode, exitStatus) => proc.finish(exitCode === 0)
            // A binary that fails to start never emits exited.
            onRunningChanged: if (!running && !proc.started) proc.finish(false)
        }
    }
}
