StatusView = require './status-view'

module.exports =
  statusView: null

  activate: ->
    cb = =>
      @statusView ?= new StatusView
      @statusView.createTermView()
      @statusView.attach()
    if atom.packages.isPackageActive 'status-bar'
      cb()
    else
      atom.packages.onDidActivateInitialPackages cb

  deactivate: ->
    @statusView.destroy()

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
