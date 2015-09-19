fs = require 'fs-plus'
{resolve} = require 'path'
{exec} = require 'child_process'
{TextEditorView} = require 'atom-space-pen-views'
{View} = require 'atom-space-pen-views'
ansihtml = require 'ansi-html-stream'
kill = require 'tree-kill'
require('fix-path')()

lastOpenedView = null

module.exports =
class CommandOutputView extends View
  # Regular expression adapted from http://blog.mattheworiordan.com/post/13174566389/url-regular-expression-for-links-with-or-without
  # Cleaned up invalid/unnecessary escapes, added negative lookahead to not match package@semver as an email address.
  rUrl: /(?:(?:(?:[A-Za-z]{3,9}:(?:\/\/)?)(?:[-;:&=+$,.\w]+@(?!\d+\.\d+\.\d+))?[A-Za-z0-9.-]+|(www\.|[-;:&=+$,.\w]+@(?!\d+\.\d+\.\d+))[A-Za-z0-9.-]+)(?:(?:\/[+~%/.\w_-]*)?\??(?:[-+=&;%@.\w]*)#?(?:[.!/\\\w]*))?)/g
  cwd: null
  @content: ->
    @div tabIndex: -1, class: 'panel panel-right ult-terminal', =>
      @div class: 'panel-heading', =>
        @div class: 'running-process-actions hide', outlet: 'runningProcessActions', =>
          @div class: 'btn-group pull-left', =>
            @button click: 'interrupt', class: 'btn', title: 'Send SIGINT to the running process (similar to pressing Ctrl+C in a regular terminal)', =>
              @span 'Interrupt'
            @button click: 'kill', class: 'btn', title: 'Send SIGKILL to the entire running process tree', =>
              @span 'Kill'
          @span ' running process', class: 'text pull-left'

        @div class: 'btn-group', =>
          @button click: 'destroy', class: 'btn', title: 'Kill the running process (if any) and destroy the terminal session', =>
            @span 'Quit'
          @button click: 'close', class: 'btn', title: 'Hide the terminal (Shift+Enter)', =>
            @span 'Hide'
      @div class: 'cli-panel-body', =>
        @pre tabIndex: -1, class: 'terminal native-key-bindings', outlet: 'cliOutput',
          'Welcome to ult-terminal.\n'
        @subview 'cmdEditor', new TextEditorView(mini: true, placeholderText: 'input your command here')

  initialize: ->
    atom.config.observe 'ult-terminal.paneWidth', (paneWidth) =>
      @css 'width', paneWidth

    @on 'click', '[data-targettype]', ->
      atom.workspace.open @dataset.target if @dataset.targettype is 'file'

    # assigned = false
    #
    # cmd = [
    #     [
    #         'test -e /etc/profile && source /etc/profile',
    #         'test -e ~/.profile && source ~/.profile',
    #         [
    #             'node -pe "JSON.stringify(process.env)"',
    #             'nodejs -pe "JSON.stringify(process.env)"',
    #             'iojs -pe "JSON.stringify(process.env)"'
    #         ].join("||")
    #     ].join(";"),
    #     'node -pe "JSON.stringify(process.env)"',
    #     'nodejs -pe "JSON.stringify(process.env)"',
    #     'iojs -pe "JSON.stringify(process.env)"'
    # ]
    #
    # for command in cmd
    #   do(command) ->
    #     if not assigned
    #       exec command, (code, stdout, stderr) ->
    #         if not assigned and not stderr
    #           try
    #             process.env = JSON.parse(stdout)
    #             assigned = true
    #           catch
    #             console.log "#{command} couldn't be loaded"

  readLine: ->
    return if this isnt lastOpenedView

    inputCmd = @cmdEditor.getModel().getText().trim()

    @appendOutput "$ #{inputCmd}\n"
    # support 'a b c' and "foo bar"
    args = inputCmd.match(/("[^"]*"|'[^']*'|[^\s'"]+)/g) ? []
    cmd = args.shift()
    if not cmd
      return
    if cmd == 'cd'
      return @cd args
    if cmd == 'ls' and !args.length
      return @ls()
    if cmd == 'clear'
      @cliOutput.empty()
      @message ''
      return @cmdEditor.setText ''
    if cmd == 'exit'
      return @destroy()
    @spawn inputCmd

  appendOutput: (output) ->
    doScroll = @isScrolledToBottom()
    @cliOutput.append output
    @scrollToBottom() if doScroll

  showCmd: ->
    doScroll = @isScrolledToBottom()
    @cmdEditor.show()
    @scrollToBottom() if doScroll
    @cmdEditor.getModel().selectAll()
    @cmdEditor.setText('') if atom.config.get('ult-terminal.clearCommandInput')
    @cmdEditor.focus()

  scrollToBottom: ->
    @cliOutput[0].scrollTop = @cliOutput[0].scrollHeight

  isScrolledToBottom: ->
    el = @cliOutput[0]
    el.scrollTop + el.offsetHeight is el.scrollHeight

  flashIconClass: (className, time = 100) =>
    @statusIcon.classList.add className
    @timer and clearTimeout(@timer)
    onStatusOut = =>
      @statusIcon.classList.remove className
    @timer = setTimeout onStatusOut, time

  # When the `destroy` method is called as an element event handler,
  # the `doKill` argument will be an event object which is truthy and the method works as expected.
  # TODO make this more explicit in the code.
  destroy: (doKill = true) ->
    _destroy = =>
      if @hasParent()
        @close()
      if @statusIcon and @statusIcon.parentNode
        @statusIcon.parentNode.removeChild(@statusIcon)
      @statusView.removeCommandView this
    if @program
      @program.once 'exit', _destroy
      @kill() if doKill
    else
      _destroy()

  kill: ->
    if @program
      kill @program.pid, 'SIGKILL', (err) ->
        console.log err if err and atom.config.get('ult-terminal.debug')

  interrupt: ->
    if @program
      # Send the interrupt signal to the root child process only, it should propagate from there.
      @program.kill 'SIGINT'

  open: ->
    @lastLocation = atom.workspace.getActivePane()

    atom.workspace.addRightPanel(item: this) unless @hasParent()

    if lastOpenedView and lastOpenedView != this
      lastOpenedView.close()
    lastOpenedView = this
    @scrollToBottom()
    @statusView.setActiveCommandView this
    @cmdEditor.focus()

  close: ->
    @lastLocation.activate()
    @detach()
    lastOpenedView = null

  toggle: ->
    if @hasParent()
      @close()
    else
      @open()

  cd: (args) ->
    args = [@getCwd()] if not args[0]
    dir = resolve @getCwd(), fs.normalize args[0]
    fs.stat dir, (err, stat) =>
      if err
        if err.code == 'ENOENT'
          return @errorMessage "cd: #{args[0]}: No such file or directory"
        return @errorMessage err.message
      if not stat.isDirectory()
        return @errorMessage "cd: not a directory: #{args[0]}"
      @cwd = dir
      @message "cwd: #{@cwd}"

  ls: () ->
    files = fs.readdirSync @getCwd()
    filesBlocks = []
    files.forEach (filename) =>
      try
        filesBlocks.push @_fileInfoHtml filename, @getCwd(), ['file-info']
      catch
        console.log "#{filename} couln't be read"
    filesBlocks = filesBlocks.sort (a, b)->
      aDir = a[1].isDirectory()
      bDir = b[1].isDirectory()
      if aDir and not bDir
        return -1
      if not aDir and bDir
        return 1
      a[2] > b[2] and 1 or -1
    filesBlocks = filesBlocks.map (b) ->
      b[0]
    @message filesBlocks.join('') + '<div class="clear"/>'

  _fileInfoHtml: (filename, parent, extraClasses = []) ->
    classes = ['icon'].concat extraClasses
    filepath = parent + '/' + filename
    stat = fs.lstatSync filepath
    if stat.isSymbolicLink()
      # classes.push 'icon-file-symlink-file'
      classes.push 'stat-link'
      stat = fs.statSync filepath
      targetType = 'null'
    if stat.isFile()
      if stat.mode & 73 #0111
        classes.push 'stat-program'
      # TODO check extension
      classes.push 'icon-file-text'
      targetType = 'file'
    if stat.isDirectory()
      classes.push 'icon-file-directory'
      targetType = 'directory'
    if stat.isCharacterDevice()
      classes.push 'stat-char-dev'
      targetType = 'device'
    if stat.isFIFO()
      classes.push 'stat-fifo'
      targetType = 'fifo'
    if stat.isSocket()
      classes.push 'stat-sock'
      targetType = 'sock'
    if filename[0] == '.'
      classes.push 'status-ignored'
    # if statusName = @getGitStatusName filepath
    #   classes.push statusName
    # other stat info
    ["<span class=\"#{classes.join ' '}\" data-targettype=\"#{targetType}\" data-target=\"#{filepath}\">#{filename}</span>", stat, filename]

  linkify: (str) ->
    escapedCwd = @getCwd().split(/[\\/]/g).map((segment) -> segment.replace /\W/g, '\\$&').join '[\\\\/]'
    rFilepath = new RegExp escapedCwd + '[\\\\/]([^\\n\\r\\t:#$%^&!:<>]+\\.?[^\\n\\r\\t:#$@%&*^!:.+,\\\\/"<>]*)', 'ig'
    str.replace rFilepath, (match, relativeFilepath) =>
      try
        @_fileInfoHtml(relativeFilepath, @getCwd())[0]
      catch err
        match
    .replace @rUrl, (match, protocolessBeginning) ->
      if protocolessBeginning
        href = (if protocolessBeginning is 'www.' then 'http://' else 'mailto:') + match
      else
        href = match
      "<a href='#{href}'>#{match}</a>"

  # getGitStatusName: (path, gitRoot, repo) ->
  #   status = (repo.getCachedPathStatus or repo.getPathStatus)(path)
  #   if status
  #     if repo.isStatusModified status
  #       return 'modified'
  #     if repo.isStatusNew status
  #       return 'added'
  #   if repo.isPathIgnore path
  #     return 'ignored'

  message: (message) ->
    @appendOutput @linkify(if message.endsWith('\n') then message else message + '\n') if message
    @showCmd()
    @statusIcon.classList.remove 'status-error'
    @statusIcon.classList.add 'status-success'

  errorMessage: (message) ->
    @appendOutput @linkify(if message.endsWith('\n') then message else message + '\n') if message
    @showCmd()
    @statusIcon.classList.remove 'status-success'
    @statusIcon.classList.add 'status-error'

  getCwd: ->
    return @cwd if @cwd?
    editorPath = atom.workspace.getActiveTextEditor()?.getPath()
    activeRootDir = null
    return @cwd = activeRootDir.path if editorPath and atom.project.rootDirectories.some (rootDir) ->
      if rootDir.contains(editorPath)
        activeRootDir = rootDir
        true
    @cwd = atom.project.rootDirectories[0]?.path ? fs.getHomeDirectory()

  spawn: (inputCmd) ->
    @cmdEditor.hide()
    htmlStream = ansihtml()
    htmlStream.on 'data', (data) =>
      return if not data
      @appendOutput @linkify data
    try
      # @program = spawn cmd, args, stdio: 'pipe', env: process.env, cwd: @getCwd()
      @program = exec inputCmd, stdio: 'pipe', env: process.env, cwd: @getCwd()
      @program.stdout.pipe htmlStream
      @program.stderr.pipe htmlStream
      @statusIcon.classList.remove 'status-success'
      @statusIcon.classList.remove 'status-error'
      @statusIcon.classList.add 'status-running'
      @runningProcessActions.removeClass 'hide'
      @program.once 'exit', (code) =>
        console.log 'exit', code if atom.config.get('ult-terminal.debug')
        @runningProcessActions.addClass 'hide'
        @statusIcon.classList.remove 'status-running'
        # @statusIcon.classList.remove 'status-error'
        @program = null
        @statusIcon.classList.add code == 0 and 'status-success' or 'status-error'
        @showCmd()
      @program.on 'error', (err) =>
        console.log 'error' if atom.config.get('ult-terminal.debug')
        @appendOutput err.message
        @showCmd()
        @statusIcon.classList.add 'status-error'
      @program.stdout.on 'data', () =>
        @flashIconClass 'status-info'
        @statusIcon.classList.remove 'status-error'
      @program.stderr.on 'data', () =>
        console.log 'stderr' if atom.config.get('ult-terminal.debug')
        @flashIconClass 'status-error', 300

    catch err
      @errorMessage err.message
      @showCmd()
