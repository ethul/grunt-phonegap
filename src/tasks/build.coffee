class module.exports.Build
  copy: require 'directory-copy'
  cp: require 'cp'
  path: require 'path'
  exec: require('child_process').exec

  constructor: (@grunt, @config) ->
    @file = @grunt.file
    @log = @grunt.log
    @warn = @grunt.warn
    @fatal = @grunt.fatal

  clean: (path = @config.path) ->
    if @file.exists(path) then @file.delete(path)
    @

  buildTree: ->
    path = @config.path
    @file.mkdir @path.join(path, 'plugins')
    @file.mkdir @path.join(path, 'platforms')
    @file.mkdir @path.join(path, 'merges', 'android')
    @file.mkdir @path.join(path, 'www')
    @file.mkdir @path.join(path, '.cordova')
    @

  cloneCordova: (fn) =>
    @copy src: @config.cordova, dest: @path.join(@config.path, '.cordova'), (err) =>
      @warn(err) if err
      fn(err) if fn

  cloneRoot: (fn) =>
    @copy src: @config.root, dest: @path.join(@config.path, 'www'), (err) =>
      @warn(err) if err
      fn(err) if fn

  compileConfig: (fn) =>
    dest = @path.join(@config.path, 'www', 'config.xml')
    if @grunt.util.kindOf(@config.config) == 'string'
      @log.writeln "Copying static #{@config.config}"
      @cp @config.config, dest, -> fn()
    else
      @log.writeln "Compiling template #{@config.config.template}"
      template = @grunt.file.read @config.config.template
      compiled = @grunt.template.process template, data: @config.config.data
      @grunt.file.write dest, compiled
      fn()

  addPlugin: (plugin, fn) =>
    cmd = "phonegap local plugin add #{plugin} #{@_setVerbosity()}"
    proc = @exec cmd, {
      cwd: @config.path,
      maxBuffer: @config.maxBuffer * 1024
    }, (err, stdout, stderr) =>
      @fatal err if err
      fn(err) if fn

    proc.stdout.on 'data', (out) => @log.write(out)
    proc.stderr.on 'data', (err) => @fatal(err)

  postProcessPlatform: (platform, fn) =>
    switch platform
      when 'android'
        @_fixAndroidVersionCode()
    fn() if fn


  buildPlatform: (platform, fn) =>
    cmd = "phonegap local build #{platform} #{@_setVerbosity()}"
    childProcess = @exec cmd, {
      cwd: @config.path,
      maxBuffer: @config.maxBuffer * 1024
    }, (err, stdout, stderr) =>
      @fatal err if err
      fn(err) if fn

    childProcess.stdout.on 'data', (out) => @log.write(out)
    childProcess.stderr.on 'data', (err) => @fatal(err)

  buildIcons: (platform, fn) =>
    if @config.icons
      switch platform
        when 'android'
          @buildAndroidIcons(@config.icons)
        when 'ios'
          @buildIosIcons(@config.name, @config.icons)
        else
          @warn "You have set `phonegap.config.icons`, but #{platform} does not support it. Skipped..."
    else
      @log.writeln "No `phonegap.config.icons` specified. Skipped."
    fn() if fn

  buildAndroidIcons: (icons) ->
    res = @path.join @config.path, 'platforms', 'android', 'res'
    best = null

    if icons['ldpi']
      best = icons['ldpi']
      @file.copy icons['ldpi'], @path.join(res, 'drawable-ldpi', 'icon.png'), encoding: null

    if icons['mdpi']
      best = icons['mdpi']
      @file.copy icons['mdpi'], @path.join(res, 'drawable-mdpi', 'icon.png'), encoding: null

    if icons['hdpi']
      best = icons['hdpi']
      @file.copy icons['hdpi'], @path.join(res, 'drawable-hdpi', 'icon.png'), encoding: null

    if icons['xhdpi']
      best = icons['xhdpi']
      @file.copy icons['xhdpi'], @path.join(res, 'drawable-xhdpi', 'icon.png'), encoding: null

    if best
      @file.copy best, @path.join(res, 'drawable', 'icon.png'), encoding: null

  buildIosIcons: (name, icons) ->
    dest = @path.join @config.path, 'platforms', 'ios', name, 'Resources', 'icons'
    enc = null
    hi = '@2x'
    small = '29'
    standard = '57'
    [small, '40', '50', standard, '60', '72', '76'].
      filter(((a) -> icons[a] && @file.exists(icons[a]) && @file.exists(icons[a + hi])), this).
      forEach((a) ->
        names =
          if a is small then ["icon-small.png", "icon-small#{hi}.png"]
          else if a is standard then ["icon.png", "icon#{hi}.png"]
          else ["icon-#{a}.png", "icon-#{a + hi}.png"]
        @file.copy icons[a], @path.join(dest, names[0]), encoding: enc
        @file.copy icons[a + hi], @path.join(dest, names[1]), encoding: enc
      , this)

  _setVerbosity: ->
    if @config.verbose then '-V' else ''

  _fixAndroidVersionCode: =>
    dom = require('xmldom').DOMParser
    data = @config.versionCode
    versionCode = if @grunt.util.kindOf(data) == 'function' then data() else data

    manifestPath = @path.join @config.path, 'platforms', 'android', 'AndroidManifest.xml'
    manifest = @grunt.file.read manifestPath
    doc = new dom().parseFromString manifest, 'text/xml'
    doc.getElementsByTagName('manifest')[0].setAttribute('android:versionCode', versionCode)
    @grunt.file.write manifestPath, doc
