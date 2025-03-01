--- tool/rbinstall.rb.orig	2021-11-09 07:21:54 UTC
+++ tool/rbinstall.rb
@@ -910,186 +910,6 @@ end
 
 # :startdoc:
 
-install?(:ext, :comm, :gem, :'default-gems', :'default-gems-comm') do
-  install_default_gem('lib', srcdir, bindir)
-end
-install?(:ext, :arch, :gem, :'default-gems', :'default-gems-arch') do
-  install_default_gem('ext', srcdir, bindir)
-end
-
-def load_gemspec(file, expanded = false)
-  file = File.realpath(file)
-  code = File.read(file, encoding: "utf-8:-")
-  code.gsub!(/(?:`git[^\`]*`|%x\[git[^\]]*\])\.split\([^\)]*\)/m) do
-    files = []
-    if expanded
-      base = File.dirname(file)
-      Dir.glob("**/*", File::FNM_DOTMATCH, base: base) do |n|
-        case File.basename(n); when ".", ".."; next; end
-        next if File.directory?(File.join(base, n))
-        files << n.dump
-      end
-    end
-    "[" + files.join(", ") + "]"
-  end
-  spec = eval(code, binding, file)
-  unless Gem::Specification === spec
-    raise TypeError, "[#{file}] isn't a Gem::Specification (#{spec.class} instead)."
-  end
-  spec.loaded_from = file
-  spec.files.reject! {|n| n.end_with?(".gemspec") or n.start_with?(".git")}
-
-  spec
-end
-
-def install_default_gem(dir, srcdir, bindir)
-  gem_dir = Gem.default_dir
-  install_dir = with_destdir(gem_dir)
-  prepare "default gems from #{dir}", gem_dir
-  RbInstall.no_write do
-    makedirs(Gem.ensure_default_gem_subdirectories(install_dir, $dir_mode).map {|d| File.join(gem_dir, d)})
-  end
-
-  options = {
-    :install_dir => with_destdir(gem_dir),
-    :bin_dir => with_destdir(bindir),
-    :ignore_dependencies => true,
-    :dir_mode => $dir_mode,
-    :data_mode => $data_mode,
-    :prog_mode => $script_mode,
-    :wrappers => true,
-    :format_executable => true,
-    :install_as_default => true,
-  }
-  default_spec_dir = Gem.default_specifications_dir
-
-  gems = Dir.glob("#{srcdir}/#{dir}/**/*.gemspec").map {|src|
-    spec = load_gemspec(src)
-    file_collector = RbInstall::Specs::FileCollector.new(src)
-    files = file_collector.collect
-    next if files.empty?
-    spec.files = files
-    spec
-  }
-  gems.compact.sort_by(&:name).each do |gemspec|
-    old_gemspecs = Dir[File.join(with_destdir(default_spec_dir), "#{gemspec.name}-*.gemspec")]
-    if old_gemspecs.size > 0
-      old_gemspecs.each {|spec| rm spec }
-    end
-
-    full_name = "#{gemspec.name}-#{gemspec.version}"
-
-    gemspec.loaded_from = File.join srcdir, gemspec.spec_name
-
-    package = RbInstall::DirPackage.new gemspec, {gemspec.bindir => 'libexec'}
-    ins = RbInstall::UnpackedInstaller.new(package, options)
-    puts "#{INDENT}#{gemspec.name} #{gemspec.version}"
-    ins.install
-  end
-end
-
-install?(:ext, :comm, :gem, :'bundled-gems') do
-  if CONFIG['CROSS_COMPILING'] == 'yes'
-    # The following hacky steps set "$ruby = BASERUBY" in tool/fake.rb
-    $hdrdir = ''
-    $extmk = nil
-    $ruby = nil  # ...
-    ruby_path = $ruby + " -I#{Dir.pwd}" # $baseruby + " -I#{Dir.pwd}"
-  else
-    # ruby_path = File.expand_path(with_destdir(File.join(bindir, ruby_install_name)))
-    ENV['RUBYLIB'] = nil
-    ENV['RUBYOPT'] = nil
-    ruby_path = File.expand_path(with_destdir(File.join(bindir, ruby_install_name))) + " --disable=gems -I#{with_destdir(archlibdir)}"
-  end
-  Gem.instance_variable_set(:@ruby, ruby_path) if Gem.ruby != ruby_path
-
-  gem_dir = Gem.default_dir
-  install_dir = with_destdir(gem_dir)
-  prepare "bundled gems", gem_dir
-  RbInstall.no_write do
-    makedirs(Gem.ensure_gem_subdirectories(install_dir, $dir_mode).map {|d| File.join(gem_dir, d)})
-  end
-
-  installed_gems = {}
-  options = {
-    :install_dir => install_dir,
-    :bin_dir => with_destdir(bindir),
-    :domain => :local,
-    :ignore_dependencies => true,
-    :dir_mode => $dir_mode,
-    :data_mode => $data_mode,
-    :prog_mode => $script_mode,
-    :wrappers => true,
-    :format_executable => true,
-  }
-  gem_ext_dir = "#$extout/gems/#{CONFIG['arch']}"
-  extensions_dir = with_destdir(Gem::StubSpecification.gemspec_stub("", gem_dir, gem_dir).extensions_dir)
-
-  File.foreach("#{srcdir}/gems/bundled_gems") do |name|
-    next if /^\s*(?:#|$)/ =~ name
-    next unless /^(\S+)\s+(\S+).*/ =~ name
-    gem_name = "#$1-#$2"
-    path = "#{srcdir}/.bundle/gems/#{gem_name}/#{gem_name}.gemspec"
-    if File.exist?(path)
-      spec = load_gemspec(path)
-    else
-      path = "#{srcdir}/.bundle/gems/#{gem_name}/#$1.gemspec"
-      next unless File.exist?(path)
-      spec = load_gemspec(path, true)
-    end
-    next unless spec.platform == Gem::Platform::RUBY
-    next unless spec.full_name == gem_name
-    if !spec.extensions.empty? && CONFIG["EXTSTATIC"] == "static"
-      puts "skip installation of #{spec.name} #{spec.version}; bundled gem with an extension library is not supported on --with-static-linked-ext"
-      next
-    end
-    spec.extension_dir = "#{extensions_dir}/#{spec.full_name}"
-    if File.directory?(ext = "#{gem_ext_dir}/#{spec.full_name}")
-      spec.extensions[0] ||= "-"
-    end
-    package = RbInstall::DirPackage.new spec
-    ins = RbInstall::UnpackedInstaller.new(package, options)
-    puts "#{INDENT}#{spec.name} #{spec.version}"
-    ins.install
-    unless $dryrun
-      File.chmod($data_mode, File.join(install_dir, "specifications", "#{spec.full_name}.gemspec"))
-    end
-    unless spec.extensions.empty?
-      install_recursive(ext, spec.extension_dir)
-    end
-    installed_gems[spec.full_name] = true
-  end
-  installed_gems, gems = Dir.glob(srcdir+'/gems/*.gem').partition {|gem| installed_gems.key?(File.basename(gem, '.gem'))}
-  unless installed_gems.empty?
-    prepare "bundled gem cache", gem_dir+"/cache"
-    install installed_gems, gem_dir+"/cache"
-  end
-  next if gems.empty?
-  if defined?(Zlib)
-    Gem.instance_variable_set(:@ruby, with_destdir(File.join(bindir, ruby_install_name)))
-    silent = Gem::SilentUI.new
-    gems.each do |gem|
-      package = Gem::Package.new(gem)
-      inst = RbInstall::GemInstaller.new(package, options)
-      inst.spec.extension_dir = with_destdir(inst.spec.extension_dir)
-      begin
-        Gem::DefaultUserInteraction.use_ui(silent) {inst.install}
-      rescue Gem::InstallError
-        next
-      end
-      gemname = File.basename(gem)
-      puts "#{INDENT}#{gemname}"
-    end
-    # fix directory permissions
-    # TODO: Gem.install should accept :dir_mode option or something
-    File.chmod($dir_mode, *Dir.glob(install_dir+"/**/"))
-    # fix .gemspec permissions
-    File.chmod($data_mode, *Dir.glob(install_dir+"/specifications/*.gemspec"))
-  else
-    puts "skip installing bundled gems because of lacking zlib"
-  end
-end
-
 parse_args()
 
 include FileUtils
