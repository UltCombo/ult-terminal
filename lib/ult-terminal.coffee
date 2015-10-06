StatusView = require './status-view'

module.exports =
  activate: (state) ->
    @statusView = new StatusView state
    cb = =>
      @statusView.createTermView()
      @statusView.attach()
    if atom.packages.isPackageActive 'status-bar'
      cb()
    else
      @statusView.subs.add atom.packages.onDidActivateInitialPackages cb

  serialize: ->
    return @statusView.state

  deactivate: ->
    @statusView.destroy()
    @statusView = null

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
    commandHistorySize:
      title: 'Command history size'
      description: 'Note that each project has its own command history.'
      type: 'integer'
      default: 500
