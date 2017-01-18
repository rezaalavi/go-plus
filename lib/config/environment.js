'use babel'

import pathhelper from './pathhelper'
import path from 'path'
var fs = require('fs')

const getenvironment = () => {
    const e = Object.assign({}, process.env)
    const g = getgopath()
    if (g) {
        e.GOPATH = g
    }
    return e
}

const getgopath = () => {

    var editor = atom.workspace.getActiveTextEditor().buffer.file
    console.log(editor);
    var project = atom.project.relativizePath(editor.path)[0]
    var fileName = ".atomenv"
    filePath = project + "/" + fileName
    console.log(filePath);
    if (fs.existsSync(filePath)) {
        var parsedObj = parseEnv(fs.readFileSync(filePath))

        let g = parsedObj.GOPATH
        if (g && g.trim() !== '') {
            return pathhelper.expand(process.env, g)
        }

    }

    // Preferred: The Environment
    let g = process.env.GOPATH
    if (g && g.trim() !== '') {
        return pathhelper.expand(process.env, g)
    }

    // Fallback: Atom Config
    g = atom.config.get('go-plus.config.gopath')
    if (g && g.trim() !== '') {
        return pathhelper.expand(process.env, g)
    }

    // Default gopath in go 1.8+
    return path.join(pathhelper.home(), 'go')
}

export {
    getenvironment,
    getgopath
}

function parseEnv(src) {
    var obj = {}

    // convert Buffers before splitting into lines and processing
    src.toString().split('\n').forEach(function(line) {
        // matching "KEY' and 'VAL' in 'KEY=VAL'
        var keyValueArr = line.match(/^\s*([\w\.\-]+)\s*=\s*(.*)?\s*$/)
        // matched?
        if (keyValueArr != null) {
            var key = keyValueArr[1]

            // default undefined or missing values to empty string
            var value = keyValueArr[2] ? keyValueArr[2] : ''

            // expand newlines in quoted values
            var len = value ? value.length : 0
            if (len > 0 && value.charAt(0) === '"' && value.charAt(len - 1) === '"') {
                value = value.replace(/\\n/gm, '\n')
            }

            // remove any surrounding quotes and extra spaces
            value = value.replace(/(^['"]|['"]$)/g, '').trim()

            obj[key] = value
        }
    })

    return obj
}
