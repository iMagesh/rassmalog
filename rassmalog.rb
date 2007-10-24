# This file is the core of Rassmalog.
#--
# Copyright 2006-2007 Suraj N. Kurapati
# See the file named LICENSE for details.

require 'rake/clean'

require 'config/format'
require 'yaml'
require 'time'
require 'ostruct'

require 'erb'
include ERB::Util


# project information

  GENERATOR = {
    :name     => 'Rassmalog',
    :version  => '7.1.0',
    :date     => '2007-10-23',
    :url      => 'http://rassmalog.rubyforge.org'
  }

  class << GENERATOR
    def to_s
      self[:name] + ' ' + self[:version]
    end

    def to_link
      link self[:url], to_s
    end
  end


# utility logic

  # Returns a hyperlink to the given URL of
  # the given name and mouse-hover title.
  def link aUrl, aName = nil, aTitle = nil
    aName ||= aUrl
    %{<a href="#{h aUrl}"#{ %{title="#{aTitle}"} if aTitle }>#{aName}</a>}
  end

  # Returns a safe file name that is composed of the
  # given words and has the given file extension.
  def make_file_name aExtension, *aWords #:nodoc:
    aWords.join(' ').to_file_name << aExtension
  end

  class String
    # Transforms this string into a vaild file name that can be safely used
    # in a URL.  See http://en.wikipedia.org/wiki/URI_scheme#Generic_syntax
    def to_file_name
      downcase.strip.gsub(%r{[/;?#[:space:][:punct:]]+}, '-')
    end

    # Transforms this UTF-8 string into HTML entities.
    def to_html_entities
      unpack('U*').map! {|c| "&##{c};"}.join
    end

    # Transforms this string into a valid URI fragment.
    # See http://www.nmt.edu/tcc/help/pubs/xhtml/id-type.html
    def to_uri_fragment
      # remove HTML tags from the input
      buf = self.gsub(/<.*?>/, '')

      # The first or only character must be a letter.
      buf.insert(0, 'a') unless buf[0,1] =~ /[[:alpha:]]/

      # The remaining characters must be letters, digits, hyphens (-),
      # underscores (_), colons (:), or periods (.) or Unicode characters
      buf.unpack('U*').map! do |code|
        if code > 0xFF or code.chr =~ /[[:alnum:]\-_:\.]/
          code
        else
          ?\s
        end
      end.pack('U*').strip.gsub(/[[:space:]-]+/, '-')
    end

    # Passes this string through ERB and returns the result.
    def thru_erb aBinding = Kernel.binding
      ERB.new(self).result(aBinding)
    end

    # Transforms this string into an escaped POSIX shell
    # argument whilst preserving Unicode characters.
    def shell_escape
      inspect.gsub(/\\(\d{3})/) {$1.to_i(8).chr}
    end


    @@uriFrags = []

    # Resets the list of uri_fragments encountered thus far.
    def String.reset_uri_fragments #:nodoc:
      @@uriFrags.clear
    end

    # Builds a table of contents from XHTML headings (<h1>, <h2>, etc.) found
    # in this string and returns an array containing [toc, text] where:
    #
    # toc::   the generated table of contents
    #
    # text::  a modified version of this string which
    #         contains anchors for the hyperlinks in
    #         the table of contents (so that the TOC
    #         can link to the content in this string)
    #
    def table_of_contents
      toc = '<ul>'
      prevDepth = 0
      prevIndex = ''

      text = gsub %r{<h(\d)(.*?)>(.*?)</h\1>$}m do
        depth, atts, title = $1.to_i, $2, $3.strip

        # generate a LaTeX-style index (section number) for the heading
          depthDiff = (depth - prevDepth).abs

          index =
            if depth > prevDepth
              toc << '<li><ul>' * depthDiff

              s = prevIndex + ('.1' * depthDiff)
              s.sub(/^\./, '')

            elsif depth < prevDepth
              toc << '</ul></li>' * depthDiff

              s = prevIndex.sub(/(\.\d+){#{depthDiff}}$/, '')
              s.next

            else
              prevIndex.next

            end

          prevDepth = depth
          prevIndex = index

        # generate a unique anchor for the heading
          frag = CGI.unescape(
            if atts =~ /id=('|")(.*?)\1/
              atts = $` + $'
              $2
            else
              title
            end
          ).to_uri_fragment

          frag << frag.object_id.to_s while @@uriFrags.include? frag
          @@uriFrags << frag

        # provide hyperlinks for traveling between TOC and heading
          dst = frag
          src = dst.object_id.to_s.to_uri_fragment

          dstUrl = '#' + dst
          srcUrl = '#' + src

          # forward link from TOC to heading
          toc << %{<li><a id="#{src}" href="#{dstUrl}">#{title}</a></li>}

          # reverse link from heading to TOC
          '<br style="display: none"/><br style="display: none"/>' << %{<h#{depth}#{atts}><a id="#{dst}" href="#{srcUrl}" class="toc-link" title="#{h LANG['return to table of contents']}">#{index}</a>&nbsp;&nbsp;&nbsp;#{title}&nbsp;<a href="#{dstUrl}" class="perma-link" rel="bookmark" title="#{LANG['permanent link to this spot']}">#</a></h#{depth}>}
      end

      if prevIndex.empty?
        toc = nil # there were no headings
      else
        toc << '</ul></li>' * prevDepth
        toc << '</ul>'

        # collapse redundant list elements
        while toc.gsub! %r{(<li>.*?)</li><li>(<ul>)}, '\1\2'
        end

        # collapse unnecessary levels
        while toc.gsub! %r{(<ul>)<li><ul>(.*)</ul></li>(</ul>)}, '\1\2\3'
        end
      end

      [toc, text]
    end
  end

  class ERB
    alias old_initialize initialize

    # A version of ERB whose embedding tags behave like those
    # of PHP.  That is, only <%= ...  %> tags produce output,
    # whereas <% ...  %> tags do *not* produce any output.
    def initialize aInput, *aArgs
      # ensure that only <%= ... %> tags generate output
        input = aInput.gsub %r{<%=.*?%>}m do |s|
          if ($' =~ /\r?\n/) == 0
            s << $&
          else
            s
          end
        end

        aArgs[1] = '>'

      old_initialize input, *aArgs
    end

    # Renders this template within a fresh object that
    # is populated with the given instance variables.
    def render_with aInstVars = {}
      dummy = Object.new

      aInstVars.each_pair do |var, val|
        dummy.instance_variable_set var, val
      end

      context = dummy.instance_eval {binding}
      result(context) # eval the ERB template
    end
  end


  # Notify the user about some action being performed.
  def notify aAction, aMessage
    printf "%12s  %s\n", aAction, aMessage
  end

  # Writes the given content to the given file.
  def write_file aPath, aContent
    File.open(aPath, 'w') {|f| f << aContent}
  end

  COMMON_DEPS = FileList[__FILE__, 'output', 'config/**/*.{yaml,*rb}']

  # Registers a new Rake task for generating a HTML
  # file and returns the path of the output file.
  def generate_html_task aTask, aPage, aDeps, aRenderOpts = {} #:nodoc:
    dst = File.join('output', aPage.url)

    # register subdirs as task deps
    dst.split('/').inject do |base, ext|
      directory base
      aDeps << base

      File.join(base, ext)
    end

    file dst => aDeps + COMMON_DEPS do
      notify aPage.class, dst
      write_file dst, aPage.render(aRenderOpts)
    end

    task aTask => dst
    CLEAN.include dst

    dst
  end


# data structures

  # Interface to translations of English strings used in the core of Rassmalog.
  class Language < Hash
    def initialize aData = {}
      merge! aData
    end

    # Translates the given string and then formats (see String#format) the
    # translation with the given placeholder arguments.  If the translation
    # is not available, then the given string will be used instead.
    def [] aPhrase, *aArgs
      s = aPhrase.to_s
      if key? s
        super(s)
      else
        s
      end.to_s % aArgs
    end
  end

  # In order to mix-in this module, an object must:
  #
  # 1. have an associated ERB template file (whose basename is
  #    specified by #template_name) in the config/ directory.
  #
  # 2. define a #url method which returns a relative URL to it.
  #
  module TemplateMixin
    # Basename of the ERB template file, which resides in the
    # config/ directory, used to render objects of this class.
    def template_name
      self.class.to_s
    end

    # Returns the ERB template used to render objects of this class.
    def template
      Kernel.const_get(template_name.to_s.upcase << '_TEMPLATE')
    end

    # Returns the name of the instance variable for objects of this
    # class.  This variable is used in the ERB template of this class.
    def template_ivar
      "@#{self.class.to_s.downcase}".to_sym
    end

    # Transforms this object into HTML.
    def to_html aOpts = {}
      aOpts[:@summarize] = BLOG.summarize_entries unless aOpts.key? :@summarize
      aOpts[template_ivar] = self
      template.render_with aOpts
    end

    # Renders a complete HTML page for this object.
    def render aOpts = {}
      aOpts[:@content] = self.to_html(aOpts)
      aOpts[:@target] = self
      aOpts[:@title]  = self.name

      html = HTML_TEMPLATE.render_with(aOpts)

      # make implicit relative paths into explicit ones
        pathPrefix = "../" * self.url.scan(%r{/+}).length

        html.gsub! %r{((?:href|src|action)\s*=\s*("|'))(.*?)(\2)} do
          head, body, tail = $1, $3.strip, $4

          if body !~ %r{^\w+:|^[/#?]}
            body.insert 0, pathPrefix
          end

          head << body << tail
        end

      html
    end

    # Returns a relative hyperlink to this object.
    def to_link aName = self.name
      link(url, aName.to_html)
    end
  end

  # A single blog entry.
  class Entry < Hash
    include TemplateMixin
      def url
        output_url
      end

    # Title of this blog entry.
    attr_reader :name

    # Date when this blog entry was written.
    attr_reader :date

    # Content of this blog entry.
    attr_reader :text

    # Categories which this blog entry belongs to.
    attr_reader :tags

    # Section object associated with the date of this blog entry.
    attr_reader :archive

    # Path to the YAML input file of this blog entry.
    attr_reader :input_file

    # Path to the HTML output file of this blog entry.
    attr_reader :output_file

    # Path (relative to the input/ directory) to
    # the YAML input file of this blog entry.
    attr_reader :input_url

    # Path (relative to the output/ directory) to
    # the HTML output file of this blog entry.
    attr_reader :output_url

    def initialize aData = {}
      merge! aData
    end

    # Returns the absolute URL to this entry.
    def absolute_url
      File.join(BLOG.url, url)
    end

    # Sort chronologically.
    def <=> aOther
      aOther.date <=> @date
    end

    # Transforms the text of this entry into HTML and returns it.
    def html
      @html ||= ERB.new(@text).render_with(template_ivar => self).to_html
    end

    # Returns a URL for submiting comments about this entry.
    def comment_url
      BLOG.email.to_url(name, File.join(BLOG.url, url))
    end
  end

  # A grouping of Entry objects based on some criteria, such as tag or archive.
  class Section < Array
    include TemplateMixin

    attr_reader :name, :chapter

    def url
      make_file_name('.html', @chapter.name, name)
    end

    def initialize aName, aChapter
      @name = aName
      @chapter = aChapter
    end

    # Returns the next section in the chapter.
    def next
      sibling(+1)
    end

    # Returns the previous section in the chapter.
    def prev
      sibling(-1)
    end

    # Sort alphabetically.
    def <=> aOther
      @name <=> aOther.name
    end

    private

    def sibling aOffset
      list = @chapter
      pos = list.index(self)

      list[(pos + aOffset) % list.length]
    end
  end

  # A list of Section objects.
  class Chapter < Array
    include TemplateMixin
      def url
        make_file_name('.html', @name)
      end

    attr_reader :name

    def initialize aName
      @name = aName
    end

    # Allows you to access a section using its name.
    def [] aName, *args
      @cache ||= Hash.new {|h,k| h[k] = find {|s| s.name == k}}
      @cache[aName] || super(aName, *args)
    end
  end

  # A list of Entry objects.  This class is used to fulfill the
  # purpose of generating a HTML page with some Entry objects on it,
  # but without resorting to the full capability of the Section class.
  class EntryList < Array #:nodoc:
    include TemplateMixin
      def url
        make_file_name('.html', name)
      end

      def template_name
        :list
      end

    attr_reader :name

    def initialize aName
      @name = aName
    end

    def to_html aOpts = {}
      aOpts[:@list] = self
      super aOpts
    end
  end


# configuration stage

  # load blog configuration
    data = YAML.load_file('config/blog.yaml')

    %w[name info author email url encoding language locale front_page].
    each do |param|
      if data.key? param and not data[param].nil?
        begin
          data[param] = data[param].to_s.thru_erb
        rescue Exception => e
          raise "unable to parse the #{param.inspect} parameter (which is specified in the main blog configuration file): #{e}"
        end
      end
    end

    BLOG = OpenStruct.new(data)

    # localize Time formats into user's language
    if locale = BLOG.locale
      begin
        require 'locale'
        Locale.setlocale(Locale::LC_ALL, locale)

      rescue SystemCallError
        raise "Your system does not support the #{locale.inspect} locale (which is specified by the 'locale' parameter in your blog configuration file)."

      rescue LoadError
        raise "Cannot activate the #{locale.inspect} locale (which is specified by the 'locale' parameter in your blog configuration file) because your system does not have the ruby-locale library."
      end
    end

    class << BLOG.menu
      # Converts this hierarchical menu into HTML.
      def to_html
        begin
          @html ||= render_menu(self)
        rescue
          warn "Error when converting BLOG.menu into HTML:"
          raise $!
        end
      end

      private

      # Expands the given hierarchical menu into an itemized list of hyperlinks.
      # * Each link name is first evaluated by ERB and then converted into HTML.
      # * Each link URL is only evaluated by ERB; there is no HTML conversion.
      def render_menu aNode
        result = ''

        if aNode.respond_to? :to_ary
          aNode.each do |node|
            result << render_menu(node)
          end

        elsif aNode.respond_to? :each_pair
          aNode.each_pair do |name, node|
            result << "<li>#{
              name = name.to_s.thru_erb.to_html

              if node.respond_to? :to_ary
                "#{name} <ul>#{render_menu node}</ul>"
              else
                url = node.to_s.thru_erb
                %{<a href="#{url}">#{name}</a>}
              end
            }</li>"
          end

        else
          result << "<li>#{aNode}</li>"
        end

        result
      end
    end

    class << BLOG.email
      # Converts this e-mail address into an obfuscated 'mailto:' URL.
      def to_url aSubject = nil, aBody = nil
        addr = "mailto:#{self.to_s.to_html_entities}"
        subj = "subject=#{u aSubject}" if aSubject
        body = "body=#{u aBody}" if aBody

        rest = [subj, body].compact
        unless rest.empty?
          addr << '?' << rest.join('&amp;')
        end

        addr
      end
    end

  # load translations
    data = YAML.load_file("config/lang/#{BLOG.language}.yaml") rescue {}
    LANG = Language.new(data)

  # load templates
    FileList['config/*.erb'].each do |f|
      name = File.basename(f, File.extname(f))
      var = "#{name.upcase}_TEMPLATE"

      Kernel.const_set var.to_sym, ERB.new(File.read(f))
    end

    class << HTML_TEMPLATE
      alias old_result result

      def result *args
        # give this page a fresh set of anchors, so that each entry's
        # table of contents does not link to other entry's contents
        String.reset_uri_fragments

        old_result(*args)
      end
    end

# input processing stage

  TAGS           = Chapter.new LANG['Tags']
  ARCHIVES       = Chapter.new LANG['Archives']
  ENTRIES        = EntryList.new LANG['Entries']
  RECENT_ENTRIES = EntryList.new LANG['Recent entries']


  tagStore = {}
  archiveStore = {}

  # hooks up the given entry with the given section (by
  # name) and chapter.  then returns the section object.
  def hookup aEntry, aStore, aName, aChapter #:nodoc:
    unless aStore.key? aName
      s = Section.new(aName, aChapter)
      aChapter << s
      aStore[aName] = s
    end

    aStore[aName] << aEntry
  end


  # generate HTML for entry files
    ENTRY_FILES = []
    ENTRY_FILES_EXCLUDED = [] # excluded from processing, so just copy them over
    entry_by_input_url = {}

    FileList['{input,entries}/**/*.yaml'].each do |src|
      begin
        data = YAML.load_file(src)

        if data.is_a? Hash and
           data.key? 'name' and
           data.key? 'text'
        then
          src =~ %r{^.*?/}
          srcDir, srcUrl = $&, $'


          entry = Entry.new(data)
          entry_by_input_url[srcUrl] = entry

          # populate the entry's methods (see Entry class definition)
          entryProp = {
            :name => data['name'].to_s.thru_erb,

            :date => entryDate = (
              if data.key? 'date'
                begin
                  Time.parse(data['date'].to_s.thru_erb)
                rescue ArgumentError => e
                  raise "unable to parse the 'date' parameter: #{e}"
                end
              else
                File.mtime(src)
              end
            ),

            :text => data['text'].to_s,

            :input_url => srcUrl,
            :input_file => src,

            :output_url => dstUrl = (
              # for entries that override the output file name
              if data.key? 'output_file'
                data['output_file'].to_s.thru_erb

              # for entries in entries/, calculate output file name
              elsif srcDir == 'entries/'
                make_file_name('.html', entryDate.strftime('%F'), data['name'])

              # for entries in input/, use the original file name
              else
                srcUrl.sub(/yaml$/, 'html')
              end
            ),

            :output_file => File.join('output', dstUrl),
          }

          if data['hide']
            entryProp[:tags] = []
            entryProp[:archive] = nil
          else
            entryProp[:tags] =
              [data['tags']].flatten.compact.uniq.sort.map do |name|
                hookup(entry, tagStore, name, TAGS)
              end

            name = entryProp[:date].strftime(BLOG.archive_frequency)
            entryProp[:archive] = hookup(entry, archiveStore, name, ARCHIVES)

            ENTRIES << entry
          end

          entryProp.each_pair do |prop, value|
            entry.instance_variable_set("@#{prop}", value)
          end

          ENTRY_FILES << src
          generate_html_task :entry, entry, [src], :@summarize => false
        else
          notify :skip, src
          ENTRY_FILES_EXCLUDED << src
        end

      rescue Exception => e
        raise "An error occurred when loading the #{src.inspect} file:\n#{e.inspect}"
      end
    end

    ENTRIES.sort! # chronological sort

  # XXX: search page depends on all entries
    if search = entry_by_input_url['search.yaml']
      file search.output_file => ENTRY_FILES
    end

  # generate list of all entries
    generate_html_task :entry_list, ENTRIES, ENTRY_FILES

  # generate list of recent entries
    recent = BLOG.num_recent_entries ? ENTRIES[0, BLOG.num_recent_entries] : ENTRIES
    recentFiles = recent.map {|e| e.input_file}

    RECENT_ENTRIES.concat recent
    generate_html_task :entry_list, RECENT_ENTRIES, recentFiles

  # generate HTML for tags and archives
    [TAGS, ARCHIVES].each do |chapter|
      chapter.sort!

      chapterDeps = []
      chapter.each do |section|
        section.sort!

        sectionDeps = section.map {|e| e.input_file}
        generate_html_task :entry_meta, section, sectionDeps

        chapterDeps.concat sectionDeps
      end

      generate_html_task :entry_meta, chapter, chapterDeps
    end


# output generation stage

  desc "Generate the blog."
  task :default => [:copy, :entry, :entry_meta, :entry_list, :feed]

  desc "Copy files from input/ into output/"
  task :copy

  desc "Generate HTML for blog entries."
  task :entry

  desc "Generate HTML for tags and archives."
  task :entry_meta

  desc "Generate HTML for recent/all entry lists."
  task :entry_list

  desc "Generate RSS feed for the blog."
  task :feed

  desc "Regenerate the blog from scratch."
  task :regen => [:clobber, :default]


  directory 'output'
  CLOBBER.include 'output'

  # copy everything from input/ into output/
    srcList = Dir.glob('input/**/*', File::FNM_DOTMATCH).
              reject {|s| File.directory? s} \
              - ENTRY_FILES + ENTRY_FILES_EXCLUDED

    dstList = srcList.map {|s| s.sub 'input', 'output'}

    task :copy => 'output' do
      srcList.zip(dstList).each do |(src, dst)|
        alreadyCopied =
          begin
            File.lstat(dst).mtime >= File.lstat(src).mtime
          rescue Errno::ENOENT
            false
          end

        unless alreadyCopied
          notify :copy, dst

          dir = File.dirname(dst)
          mkdir_p dir unless File.directory? dir

          remove_entry_secure dst, true
          copy_entry src, dst, !File.symlink?(src)
        end
      end
    end

  # generate the front page
    dst = 'output/index.html'

    file dst => COMMON_DEPS do
      target = BLOG.front_page || RECENT_ENTRIES.url
      targetUrl = target.split('/').map {|s| u(s)}.join('/')

      notify 'front page', File.join('output', target)
      write_file dst, %{<META HTTP-EQUIV="Refresh" CONTENT="0; URL=#{targetUrl}">}
    end

    task :entry_list => dst
    CLEAN.include dst

  # generate the RSS feed
    file 'output/rss.xml' => COMMON_DEPS + ENTRY_FILES do |t|
      notify 'RSS feed', t.name
      write_file t.name, RSS_TEMPLATE.result(binding)
    end

    task :feed => 'output/rss.xml'
    CLEAN.include 'output/rss.xml'


# output publishing stage

  desc "Upload the blog to your website."
  task :upload => [:default, 'output'] do
    whole = 'output'
    parts = Dir.glob('output/*', File::FNM_DOTMATCH)[2..-1].
            map {|f| f.shell_escape}.join(' ')

    sh BLOG.uploader.to_s.thru_erb(binding)
  end


# utility tasks

  IMPORT_DIR = 'import'
  directory IMPORT_DIR

  desc "Import blog entries from RSS feed on STDIN."
  task :import => IMPORT_DIR do
    require 'cgi'
    require 'rexml/document'

    REXML::Document.new(STDIN.read).each_element '//item' do |src|
      name = CGI.unescapeHTML src.elements['title'].text
      date = src.elements['pubDate'].text rescue Time.now
      tags = src.get_elements('category').map {|e| e.text} rescue []
      text = CGI.unescapeHTML src.elements['description'].text
      from = CGI.unescape src.elements['link'].text

      dstFile = make_file_name('.yaml', date.strftime('%F'), name)
      dst = File.join(IMPORT_DIR, dstFile)

      entry = %w[from name date tags].
        map {|var| {var => eval(var)}.to_yaml.sub(/^---\s*$/, '')}.
        join << "\ntext: |\n#{text.gsub(/^/, '  ')}"

      notify :import, dst
      write_file dst, entry
    end
  end
