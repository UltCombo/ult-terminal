UltTerminalView = require './ult-terminal-view'

module.exports =
  cliStatusView: null

  activate: (state) ->
    cb = =>
      @cliStatusView ?= new UltTerminalView(state.cliStatusViewState)
      @cliStatusView.createCommandView()
      @cliStatusView.attach()
    if atom.packages.isPackageActive 'status-bar'
      cb()
    else
      atom.packages.onDidActivateInitialPackages cb

  deactivate: ->
    @cliStatusView.destroy()

  config:
    paneWidth:
      title: 'Pane width (px)'
      type: 'integer'
      default: 520
    clearCommandInput:
      title: 'Clear command input after submitting command'
      type: 'boolean'
      default: true
    debug:
      title: 'Output debugging information to console'
      type: 'boolean'
      default: false
