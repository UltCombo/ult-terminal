{View} = require 'atom-space-pen-views'
CommandOutputView = require './command-output-view'

module.exports =
class UltTerminalView extends View
  @content: ->
    @div class: 'ult-terminal inline-block', =>
      @span outlet: 'termStatusContainer', =>
        @span click: 'newTermClick', class: 'ult-terminal icon icon-plus'

  commandViews: []
  activeIndex: 0
  initialize: (serializeState) ->

    atom.commands.add 'atom-workspace',
      'ult-terminal:new': => @newTermClick()
      'ult-terminal:toggle': => @toggle()
      'ult-terminal:next': => @activeNextCommandView()
      'ult-terminal:prev': => @activePrevCommandView()
      'ult-terminal:destroy': => @destroyActiveTerm()

     atom.commands.add '.panel.ult-terminal', 'core:confirm', => @runActiveTermCommand()

  createCommandView: ->
    termStatus = document.createElement 'span'
    termStatus.className = 'ult-terminal icon icon-terminal'
    commandOutputView = new CommandOutputView
    commandOutputView.statusIcon = termStatus
    commandOutputView.statusView = this
    @commandViews.push commandOutputView
    termStatus.addEventListener 'click', ->
      commandOutputView.toggle()
    @termStatusContainer.append termStatus
    commandOutputView

  activeNextCommandView: ->
    @activeCommandView @activeIndex + 1

  activePrevCommandView: ->
    @activeCommandView @activeIndex - 1

  activeCommandView: (index) ->
    if index >= @commandViews.length
      index = 0
    else if index < 0
      index = @commandViews.length - 1
    @commandViews[index]?.open()

  setActiveCommandView: (commandView) ->
    @activeIndex = @commandViews.indexOf commandView

  removeCommandView: (commandView) ->
    index = @commandViews.indexOf commandView
    index >=0 and @commandViews.splice index, 1
    @activeIndex-- if not @commandViews[@activeIndex]? and @activeIndex > 0

  newTermClick: ->
    @createCommandView().toggle()

  attach: (statusBar) ->
    statusBar = document.querySelector("status-bar")
    if statusBar?
      @statusBarTile = statusBar.addLeftTile(item: this, priority: 100)

  destroyActiveTerm: ->
    @commandViews[@activeIndex]?.destroy()

  runActiveTermCommand: ->
    @commandViews[@activeIndex]?.readLine()

  # Tear down any state and detach
  destroy: ->
    for index in [@commandViews.length - 1 .. 0] by -1
      @commandViews[index].destroy false
    if @commandViews.length
      pids = (commandView.program.pid for commandView in @commandViews)
      require('child_process').fork(__dirname + '/kill-all.js', pids).unref()
    @detach()

  toggle: ->
    @createCommandView() unless @commandViews[@activeIndex]?
    @commandViews[@activeIndex].toggle()
