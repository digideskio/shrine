require "test_helper"
require "shrine/plugins/logging"
require "stringio"
require "logger"

describe Shrine::Plugins::Logging do
  def log
    @uploader.opts[:logging_stream].string
  end

  before do
    @uploader = uploader { plugin :logging, stream: StringIO.new }
    @context = {name: :avatar, phase: :store}
    @context[:record] = Object.const_set("User", Struct.new(:id)).new(16)
  end

  after do
    Object.send(:remove_const, "User")
  end

  it "logs processing" do
    @uploader.upload(fakeio)
    refute_match /PROCESS/, log

    @uploader.instance_eval { def process(io, context); io; end }
    @uploader.upload(fakeio)
    assert_match /PROCESS \S+ 1-1 file \(\d+\.\d+s\)$/, log
  end

  it "logs storing" do
    @uploader.upload(fakeio)
    assert_match /STORE \S+ 1 file \(\d+\.\d+s\)$/, log
  end

  it "logs deleting" do
    uploaded_file = @uploader.upload(fakeio)
    @uploader.delete(uploaded_file)
    assert_match /DELETE \S+ 1 file \(\d+\.\d+s\)$/, log
  end

  it "counts versions" do
    @uploader.class.plugin :versions
    @uploader.instance_eval do
      def process(io, context)
        {thumb: StringIO.new, original: StringIO.new}
      end
    end

    versions = @uploader.upload(fakeio)
    @uploader.delete(versions)

    assert_match /PROCESS \S+ 1-2 files/, log
    assert_match /STORE \S+ 2 files/, log
    assert_match /DELETE \S+ 2 files/, log
  end

  it "counts array of files" do
    @uploader.class.plugin :multi_delete
    @uploader.delete([@uploader.upload(fakeio), @uploader.upload(fakeio)])
    assert_match /DELETE \S+ 2 files/, log
  end

  it "outputs context data" do
    @uploader.instance_eval { def process(io, context); io; end }

    uploaded_file = @uploader.upload(fakeio, @context)
    @uploader.delete(uploaded_file, @context)

    assert_match /PROCESS\[store\] \S+\[:avatar\] User\[16\] 1-1 file \(\d+\.\d+s\)$/, log
    assert_match /STORE\[store\] \S+\[:avatar\] User\[16\] 1 file \(\d+\.\d+s\)$/, log
    assert_match /DELETE\[store\] \S+\[:avatar\] User\[16\] 1 file \(\d+\.\d+s\)$/, log
  end

  it "supports JSON format" do
    @uploader.opts[:logging_format] = :json
    @uploader.upload(fakeio, @context)
    JSON.parse(log[/\{.+\}/])
  end

  it "supports Heroku-style format" do
    @uploader.opts[:logging_format] = :heroku
    @uploader.upload(fakeio, @context)
    assert_match "action=store phase=store", log
  end

  it "accepts a custom logger" do
    @uploader.class.logger = (logger = Logger.new(nil))
    assert_equal logger, @uploader.class.logger
  end

  it "accepts model instances without an #id" do
    @context[:record].instance_eval { undef id }
    @uploader.upload(fakeio, @context)
    assert_match /STORE\[store\] \S+\[:avatar\] User 1 file \(\d+\.\d+s\)$/, log
  end

  it "works with hooks plugin in the right order" do
    @uploader = uploader do
      plugin :logging, stream: StringIO.new
      plugin :hooks
    end

    @uploader.class.class_eval do
      def around_store(io, context)
        self.class.logger.info "before logging"
        super
        self.class.logger.info "after logging"
      end
    end

    @uploader.upload(fakeio)

    assert_match "before logging", log.lines[0]
    assert_match "after logging",  log.lines[1]
    assert_match "STORE",          log.lines[2]
  end
end
