{View} = require 'atom-space-pen-views'
TermView = require './term-view'

module.exports =
class StatusView extends View
  @content: ->
    @div class: 'ult-terminal-status inline-block', =>
      @span outlet: 'termStatusContainer', =>
        @span click: 'onNewTerm', class: 'icon icon-plus'

  termViews: []
  activeIndex: 0
  initialize: ->

    atom.commands.add 'atom-workspace',
      'ult-terminal:new': => @onNewTerm()
      'ult-terminal:toggle': => @toggle()
      'ult-terminal:next': => @activateNextTermView()
      'ult-terminal:prev': => @activatePrevTermView()
      'ult-terminal:destroy': => @destroyActiveTerm()

     atom.commands.add '.panel.ult-terminal', 'core:confirm', => @runActiveTermCommand()

  createTermView: ->
    termStatus = document.createElement 'span'
    termStatus.className = 'icon icon-terminal'
    termView = new TermView
    termView.statusIcon = termStatus
    termView.statusView = this
    @termViews.push termView
    termStatus.addEventListener 'click', ->
      termView.toggle()
    @termStatusContainer.append termStatus
    termView

  activateNextTermView: ->
    @activateTermView @activeIndex + 1

  activatePrevTermView: ->
    @activateTermView @activeIndex - 1

  activateTermView: (index) ->
    if index >= @termViews.length
      index = 0
    else if index < 0
      index = @termViews.length - 1
    @termViews[index]?.open()

  setActiveTermView: (termView) ->
    @activeIndex = @termViews.indexOf termView

  removeTermView: (termView) ->
    index = @termViews.indexOf termView
    index >=0 and @termViews.splice index, 1
    @activeIndex-- if not @termViews[@activeIndex]? and @activeIndex > 0

  onNewTerm: ->
    @createTermView().toggle()

  attach: (statusBar) ->
    statusBar = document.querySelector("status-bar")
    if statusBar?
      @statusBarTile = statusBar.addLeftTile(item: this, priority: 100)

  destroyActiveTerm: ->
    @termViews[@activeIndex]?.destroy()

  runActiveTermCommand: ->
    @termViews[@activeIndex]?.readLine()

  # Tear down any state and detach
  destroy: ->
    for index in [@termViews.length - 1 .. 0] by -1
      @termViews[index].destroy false
    if @termViews.length
      pids = (termView.program.pid for termView in @termViews)
      require('child_process').fork(__dirname + '/kill-all.js', pids).unref()
    @detach()

  toggle: ->
    @createTermView() unless @termViews[@activeIndex]?
    @termViews[@activeIndex].toggle()
