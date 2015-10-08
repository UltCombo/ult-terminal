{View} = require 'atom-space-pen-views'
SubAtom = require 'sub-atom'
TermView = require './term-view'

module.exports =
class StatusView extends View
  @content: ->
    @div class: 'ult-terminal-status inline-block', =>
      @span outlet: 'termStatusContainer', =>
        @span outlet: 'newTerminalButton', click: 'onNewTerm', class: 'icon icon-plus', title: 'Open new terminal'

  initialize: (state) ->
    @state = state ? {}
    @state.commandHistory ?= []
    @termViews = []
    @activeIndex = 0
    @subs = new SubAtom

    @subs.add atom.commands.add 'atom-workspace',
      'ult-terminal:new': => @onNewTerm()
      'ult-terminal:toggle': => @toggle()
      'ult-terminal:next': => @activateNextTermView()
      'ult-terminal:prev': => @activatePrevTermView()
      'ult-terminal:destroy': => @destroyActiveTerm()

    @subs.add atom.commands.add '.panel.ult-terminal', 'core:confirm', => @runActiveTermCommand()

    @subs.add atom.tooltips.add @newTerminalButton, {}

  createTermView: ->
    statusIcon = document.createElement 'span'
    statusIcon.className = 'icon icon-terminal'
    termView = new TermView statusIcon, this, @state.commandHistory[..]
    @termViews.push termView
    @termStatusContainer.append statusIcon
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
    statusBar = document.querySelector 'status-bar'
    if statusBar?
      @statusBarTile = statusBar.addLeftTile item: this, priority: 100

  destroyActiveTerm: ->
    @termViews[@activeIndex]?.destroy()

  runActiveTermCommand: ->
    @termViews[@activeIndex]?.readLine()

  # Tear down any state and remove
  destroy: ->
    for index in [@termViews.length - 1 .. 0] by -1
      @termViews[index].destroy()
    @remove()
    @subs.dispose()

  toggle: ->
    @createTermView() unless @termViews[@activeIndex]?
    @termViews[@activeIndex].toggle()
