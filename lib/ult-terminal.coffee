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
      type: 'integer'
      default: 520
    clearCommandInput:
      type: 'boolean'
      default: true
    logConsole:
      type: 'boolean'
      default: false
