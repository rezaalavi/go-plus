{Subscriber, Emitter} = require 'emissary'
Gofmt = require './gofmt'
Govet = require './govet'
Golint = require './golint'
Gopath = require './gopath'
Gobuild = require './gobuild'
Gocov = require './gocov'
Executor = require './executor'
GoExecutable = require './goexecutable'
SplicerSplitter = require './util/splicersplitter'
_ = require 'underscore-plus'
{MessagePanelView, LineMessageView, PlainMessageView} = require 'atom-message-panel'
{$} = require 'atom'
path = require 'path'

module.exports =
class Dispatch
  Subscriber.includeInto(this)
  Emitter.includeInto(this)

  constructor: ->
    # Manage Save Pipeline
    @dispatching = false
    @ready = false
    @actionqueue = []
    @collectionqueue = []
    @messages = []

    @processEnv = process.env
    @executor = new Executor()
    @splicersplitter = new SplicerSplitter()
    @goexecutable = new GoExecutable(@processEnv)
    @goexecutable.on 'detect-complete', =>
      @ready = true
      @emit 'ready'
    @goexecutable.detect()

    @gofmt = new Gofmt(this)
    @govet = new Govet(this)
    @golint = new Golint(this)
    @gopath = new Gopath(this)
    @gobuild = new Gobuild(this)
    @gocov = new Gocov(this)
    @messagepanel = new MessagePanelView title: '<span class="icon-diff-added"></span> go-plus', rawTitle: true

    # Pipeline For Processing Buffer
    @gofmt.on 'fmt-complete', (editorView, saving) =>
      @emit 'fmt-complete', editorView, saving
      @govet.checkBuffer(editorView, saving) if saving
      @emit 'dispatch-complete', editorView if not saving
    @govet.on 'vet-complete', (editorView, saving) =>
      @emit 'vet-complete', editorView, saving
      @golint.checkBuffer(editorView, saving) if saving
      @emit 'dispatch-complete', editorView if not saving
    @golint.on 'lint-complete', (editorView, saving) =>
      @emit 'lint-complete', editorView, saving
      @gopath.check(editorView, saving) if saving
      @emit 'dispatch-complete', editorView if not saving
    @gopath.on 'gopath-complete', (editorView, saving) =>
      @emit 'gopath-complete', editorView, saving
      @gobuild.checkBuffer(editorView, saving) if saving
      @emit 'dispatch-complete', editorView if not saving
    @gobuild.on 'syntaxcheck-complete', (editorView, saving) =>
      @emit 'syntaxcheck-complete', editorView, saving
      @emit 'dispatch-complete', editorView

    # Collect Messages
    @gocov.on 'gocov-messages', (editorView, messages) =>
      @collectMessages(messages)
    @gofmt.on 'fmt-messages', (editorView, messages) =>
      @collectMessages(messages)
    @govet.on 'vet-messages', (editorView, messages) =>
      @collectMessages(messages)
    @golint.on 'lint-messages', (editorView, messages) =>
      @collectMessages(messages)
    @gopath.on 'gopath-messages', (editorView, messages) =>
      @collectMessages(messages)
    @gobuild.on 'syntaxcheck-messages', (editorView, messages) =>
      @collectMessages(messages)

    # Reset State If Requested
    @gofmt.on 'reset', (editorView) =>
      @resetState(editorView)
    @golint.on 'reset', (editorView) =>
      @resetState(editorView)
    @govet.on 'reset', (editorView) =>
      @resetState(editorView)
    @gopath.on 'reset', (editorView) =>
      @resetState(editorView)
    @gobuild.on 'reset', (editorView) =>
      @resetState(editorView)
    @gocov.on 'reset', (editorView) =>
      @resetState(editorView)

    # Update Pane And Gutter With Messages
    @on 'dispatch-complete', (editorView) =>
      @updatePane(editorView, @messages)
      @updateGutter(editorView, @messages)
      @dispatching = false
      @emit 'display-complete'

    atom.workspaceView.eachEditorView (editorView) => @handleEvents(editorView)
    atom.workspaceView.on 'pane-container:active-pane-item-changed', =>
        @resetPanel()
        @messagepanel.close()

  collectMessages: (messages) ->
    @messages = _.union(@messages, messages)
    @messages = _.uniq @messages, (element, index, list) ->
      return element.line + ":" + element.column + ":" + element.msg
    @emit 'messages-collected', _.size(@messages)

  destroy: ->
    @unsubscribe()
    @gocov.destroy()
    @gobuild.destroy()
    @golint.destroy()
    @govet.destroy()
    @gopath.destroy()
    @gofmt.destroy()

  handleEvents: (editorView) ->
    editor = editorView.getEditor()
    buffer = editor.getBuffer()
    buffer.on 'changed', => @handleBufferChanged(editorView)
    buffer.on 'saved', =>
      return unless not @dispatching
      @dispatching = true
      @handleBufferSave(editorView, true)
    editor.on 'destroyed', => buffer.off 'saved'

  handleBufferSave: (editorView, saving) ->
    editor = editorView.getEditor()
    grammar = editor.getGrammar()
    return if grammar.scopeName isnt 'source.go'
    @resetState(editorView)
    @gofmt.formatBuffer(editorView, saving)
    if atom.config.get('go-plus.runCoverageOnSave')
      @gocov.runCoverage(editorView)

  handleBufferChanged: (editorView) ->
    @gocov.resetCoverage()

  resetState: (editorView) ->
    @messages = []
    @resetGutter(editorView)
    @resetPanel()

  resetGutter: (editorView) ->
    gutter = editorView?.gutter
    return unless gutter?
    gutter.removeClassFromAllLines('go-plus-message')

  updateGutter: (editorView, messages) ->
    @resetGutter(editorView)
    return unless messages?
    return if messages.length <= 0
    gutter = editorView?.gutter
    return unless gutter?
    gutter.addClassToLine message.line - 1, 'go-plus-message' for message in messages

  resetPanel: ->
    @messagepanel.close()
    @messagepanel.clear()

  updatePane: (editorView, messages) ->
    @resetPanel
    return unless messages?
    if messages.length <= 0 and atom.config.get('go-plus.showPanelWhenNoIssuesExist')
      @messagepanel.add new PlainMessageView message: 'No Issues', className: 'text-success'
      @messagepanel.attach()
      return
    return unless messages.length > 0
    return unless atom.config.get('go-plus.showPanel')
    sortedMessages = _.sortBy @messages, (element, index, list) ->
      return parseInt(element.line, 10)
    for message in sortedMessages
      className = switch message.type
        when 'error' then 'text-error'
        when 'warning' then 'text-warning'
        else 'text-info'

      if message.line isnt false and message.column isnt false
        # LineMessageView
        @messagepanel.add new LineMessageView line: message.line, character: message.column, message: message.msg, className: className
      else if message.line isnt false and message.column is false
        # LineMessageView
        @messagepanel.add new LineMessageView line: message.line, message: message.msg, className: className
      else
        # PlainMessageView
        @messagepanel.add new PlainMessageView message: message.msg, className: className
    @messagepanel.attach() if atom?.workspaceView?

  isValidEditorView: (editorView) ->
    editorView?.getEditor()?.getGrammar()?.scopeName is 'source.go'

  env: ->
    envCopy = $.extend(true, {}, @processEnv)
    envCopy
