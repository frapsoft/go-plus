{spawn} = require 'child_process'
{Subscriber, Emitter} = require 'emissary'
_ = require 'underscore-plus'

module.exports =
class Golint
  Subscriber.includeInto(this)
  Emitter.includeInto(this)

  constructor: (dispatch) ->
    atom.workspaceView.command 'golang:golint', => @checkCurrentBuffer()
    @dispatch = dispatch
    @name = 'lint'

  destroy: ->
    @unsubscribe()

  reset: (editorView) ->
    @emit 'reset', editorView

  checkCurrentBuffer: ->
    editorView = atom.workspaceView.getActiveView()
    return unless editorView?
    @reset editorView
    @checkBuffer(editorView, false)

  checkBuffer: (editorView, saving) ->
    unless @dispatch.isValidEditorView(editorView)
      @emit @name + '-complete', editorView, saving
      return
    if saving and not atom.config.get('go-plus.lintOnSave')
      @emit @name + '-complete', editorView, saving
      return
    buffer = editorView?.getEditor()?.getBuffer()
    unless buffer?
      @emit @name + '-complete', editorView, saving
      return
    args = [buffer.getPath()]
    configArgs = @dispatch.splicersplitter.splitAndSquashToArray(' ', atom.config.get('go-plus.golintArgs'))
    args = configArgs.concat(args) if configArgs? and _.size(configArgs) > 0
    cmd = atom.config.get('go-plus.golintPath')
    errored = false
    proc = spawn(cmd, args)
    proc.on 'error', (error) =>
      return unless error?
      errored = true
      console.log @name + ': error launching command [' + cmd + '] – ' + error  + ' – current PATH: [' + @dispatch.env().PATH + ']'
      messages = []
      message = line: false, column: false, type: 'error', msg: 'Golint Executable Not Found @ ' + cmd + ' ($GOPATH: ' + @dispatch.buildGoPath() + ')'
      messages.push message
      @emit @name + '-messages', editorView, messages
      @emit @name + '-complete', editorView, saving
    proc.stderr.on 'data', (data) => console.log @name + ': ' + data if data?
    proc.stdout.on 'data', (data) => @mapMessages(editorView, data)
    proc.on 'close', (code) =>
      console.log @name + ': [' + cmd + '] exited with code [' + code + ']' if code isnt 0
      @emit @name + '-complete', editorView, saving unless errored

  mapMessages: (editorView, data) ->
    pattern = /^(.*?):(\d*?):((\d*?):)?\s(.*)$/img
    messages = []
    extract = (matchLine) ->
      return unless matchLine?
      message = switch
        when matchLine[4]?
          line: matchLine[2]
          column: matchLine[4]
          msg: matchLine[5]
          type: 'warning'
          source: 'lint'
        else
          line: matchLine[2]
          column: false
          msg: matchLine[5]
          type: 'warning'
          source: 'lint'
      messages.push message
    loop
      match = pattern.exec(data)
      extract(match)
      break unless match?
    @emit @name + '-messages', editorView, messages
