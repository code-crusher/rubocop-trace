# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Lint::UnreachableCode, :config do
  def wrap(str)
    head = <<~RUBY
      def something
        array.each do |item|
    RUBY
    tail = <<~RUBY
        end
      end
    RUBY
    body = str.each_line.map { |line| "    #{line}" }.join
    head + body + tail
  end

  it 'registers a single offense on the statement that makes the following code unreachable' do
    expect_offense(wrap(<<~RUBY))
      return
      ^^^^^^ Code following an always-true guard statement will never run.
      bar
      baz
    RUBY
  end

  it 'registers an offense on the guard rather than on the unreachable code' do
    expect_offense(<<~RUBY)
      def main
        return # if 2 + 2 == 4
        ^^^^^^ Code following an always-true guard statement will never run.

        _meaning = 42
        puts 'Whatever you say'
        raise PizzaDough if Date.today.friday?
      end
    RUBY
  end

  it 'registers a single offense when a guard contains unreachable code itself' do
    expect_offense(<<~RUBY)
      def main
        if cond
        ^^^^^^^ Code following an always-true guard statement will never run.
          return
          unreachable
        else
          return
          unreachable
        end
        also_unreachable
      end
    RUBY
  end

  it 'registers a single offense when an unconditional `begin` is followed by code' do
    expect_offense(<<~RUBY)
      def main
        begin
          return
          ^^^^^^ Code following an always-true guard statement will never run.
          unreachable
        end
        also_unreachable
      end
    RUBY
  end

  it 'registers an offense for a guard that is the only expression of a `begin`' do
    expect_offense(<<~RUBY)
      def main
        begin
          return
          ^^^^^^ Code following an always-true guard statement will never run.
          unreachable
        end
      end
    RUBY
  end

  %w[return next break retry redo throw raise fail exit exit! abort].each do |t|
    # The syntax using `retry` is not supported in Ruby 3.3 and later.
    next if t == 'retry' && ENV['PARSER_ENGINE'] == 'parser_prism'

    it "registers an offense for `#{t}` before other statements" do
      expect_offense(wrap(<<~RUBY), t: t)
        %{t}
        ^{t} Code following an always-true guard statement will never run.
        bar
      RUBY
    end

    it "registers an offense for `#{t}` in `begin`" do
      expect_offense(wrap(<<~RUBY), t: t)
        begin
          %{t}
          ^{t} Code following an always-true guard statement will never run.
          bar
        end
      RUBY
    end

    it "registers an offense for `#{t}` in all `if` branches" do
      expect_offense(wrap(<<~RUBY), t: t)
        if cond
        ^^^^^^^ Code following an always-true guard statement will never run.
          %{t}
        else
          %{t}
        end
        bar
      RUBY
    end

    it "registers an offense for `#{t}` in all `if` branches with other expressions" do
      expect_offense(wrap(<<~RUBY), t: t)
        if cond
        ^^^^^^^ Code following an always-true guard statement will never run.
          something
          %{t}
        else
          something2
          %{t}
        end
        bar
      RUBY
    end

    it "registers an offense for `#{t}` in all `if` and `elsif` branches" do
      expect_offense(wrap(<<~RUBY), t: t)
        if cond
        ^^^^^^^ Code following an always-true guard statement will never run.
          something
          %{t}
        elsif cond2
          something2
          %{t}
        else
          something3
          %{t}
        end
        bar
      RUBY
    end

    it "registers an offense for `#{t}` in all `case` branches" do
      expect_offense(wrap(<<~RUBY), t: t)
        case cond
        ^^^^^^^^^ Code following an always-true guard statement will never run.
        when 1
          something
          %{t}
        when 2
          something2
          %{t}
        else
          something3
          %{t}
        end
        bar
      RUBY
    end

    it "registers an offense for `#{t}` in all `case` pattern branches" do
      expect_offense(wrap(<<~RUBY), t: t)
        case cond
        ^^^^^^^^^ Code following an always-true guard statement will never run.
        in 1
          something
          %{t}
        in 2
          something2
          %{t}
        else
          something3
          %{t}
        end
        bar
      RUBY
    end

    it "accepts code with conditional `#{t}`" do
      expect_no_offenses(wrap(<<~RUBY))
        #{t} if cond
        bar
      RUBY
    end

    it "accepts `#{t}` as the final expression" do
      expect_no_offenses(wrap(<<~RUBY))
        #{t} if cond
      RUBY
    end

    it "accepts `#{t}` is in all `if` branches" do
      expect_no_offenses(wrap(<<~RUBY))
        if cond
          #{t}
        else
          #{t}
        end
      RUBY
    end

    it "accepts `#{t}` is in `if` branch only" do
      expect_no_offenses(wrap(<<~RUBY))
        if cond
          something
          #{t}
        else
          something2
        end
        bar
      RUBY
    end

    it "accepts `#{t}` is in `if`, and without `else`" do
      expect_no_offenses(wrap(<<~RUBY))
        if cond
          something
          #{t}
        end
        bar
      RUBY
    end

    it "accepts `#{t}` is in `else` branch only" do
      expect_no_offenses(wrap(<<~RUBY))
        if cond
          something
        else
          something2
          #{t}
        end
        bar
      RUBY
    end

    it "accepts `#{t}` is not in `elsif` branch" do
      expect_no_offenses(wrap(<<~RUBY))
        if cond
          something
          #{t}
        elsif cond2
          something2
        else
          something3
          #{t}
        end
        bar
      RUBY
    end

    it "accepts `#{t}` is in `case` branch without else" do
      expect_no_offenses(wrap(<<~RUBY))
        case cond
        when 1
          something
          #{t}
        when 2
          something2
          #{t}
        end
        bar
      RUBY
    end

    it "accepts `#{t}` is in `case` pattern branch without else" do
      expect_no_offenses(wrap(<<~RUBY))
        case cond
        in 1
          something
          #{t}
        in 2
          something2
          #{t}
        end
        bar
      RUBY
    end

    # These are keywords and cannot be redefined.
    next if %w[return next break retry redo].include? t

    it "registers an offense for `#{t}` after `instance_eval`" do
      expect_offense(<<~RUBY, t: t)
        class Dummy
          def %{t}; end
        end

        d = Dummy.new
        d.instance_eval do
          %{t}
          bar
        end

        %{t}
        ^{t} Code following an always-true guard statement will never run.
        bar
      RUBY
    end

    it "registers an offense for `#{t}` with nested redefinition" do
      expect_offense(<<~RUBY, t: t)
        def foo
          def %{t}; end
        end

        %{t}
        ^{t} Code following an always-true guard statement will never run.
        bar
      RUBY
    end

    it "accepts `#{t}` if redefined" do
      expect_no_offenses(wrap(<<~RUBY))
        def #{t}; end
        #{t}
        bar
      RUBY
    end

    it "accepts `#{t}` if redefined even if it's called recursively" do
      expect_no_offenses(wrap(<<~RUBY))
        def #{t}
          #{t}
          bar
        end

        #{t}
        bar
      RUBY
    end

    it "registers an offense for `self.#{t}` with nested redefinition" do
      expect_offense(<<~RUBY, t: t)
        def foo
          def self.%{t}; end
        end

        %{t}
        ^{t} Code following an always-true guard statement will never run.
        bar
      RUBY
    end

    it "accepts `self.#{t}` if redefined" do
      expect_no_offenses(wrap(<<~RUBY))
        def self.#{t}; end
        #{t}
        bar
      RUBY
    end

    it "accepts `self.#{t}` if redefined even if it's called recursively" do
      expect_no_offenses(wrap(<<~RUBY))
        def self.#{t}
          #{t}
          bar
        end

        #{t}
        bar
      RUBY
    end

    it "accepts `#{t}` if called in `instance_eval`" do
      expect_no_offenses <<~RUBY
        class Dummy
          def #{t}; end
        end

        d = Dummy.new
        d.instance_eval do
          #{t}
          bar
        end
      RUBY
    end

    it "accepts `#{t}` if called in `instance_eval` with numblock" do
      expect_no_offenses <<~RUBY
        class Dummy
          def #{t}; end
        end

        d = Dummy.new
        d.instance_eval do
          #{t}
          _1
        end
      RUBY
    end

    it "accepts `#{t}` if called in `instance_eval` with itblock", :ruby34 do
      expect_no_offenses <<~RUBY
        class Dummy
          def #{t}; end
        end

        d = Dummy.new
        d.instance_eval do
          #{t}
          it
        end
      RUBY
    end

    it "accepts `#{t}` if called in nested `instance_eval`" do
      expect_no_offenses <<~RUBY
        class Dummy
          def #{t}; end
        end

        d = Dummy.new
        d.instance_eval do
          d2 = Dummy.new
          d2.instance_eval do
            #{t}
            bar
          end
        end
      RUBY
    end

    it "registers an offense for redefined `#{t}` if it is called on Kernel" do
      expect_offense(<<~RUBY, t: t)
        def %{t}; end

        Kernel.%{t}
        ^^^^^^^^{t} Code following an always-true guard statement will never run.
        foo
      RUBY
    end

    it "accepts redefined `#{t}` if it is called on a class other than Kernel" do
      expect_no_offenses <<~RUBY
        def #{t}; end

        Dummy.#{t}
        foo
      RUBY
    end

    it "registers an offense for `#{t}` inside `instance_eval` if it is called on Kernel" do
      expect_offense(<<~RUBY, t: t)
        class Dummy
          def %{t}; end
        end

        d = Dummy.new
        d.instance_eval do
          Kernel.%{t}
          ^^^^^^^^{t} Code following an always-true guard statement will never run.
          foo
        end
      RUBY
    end

    it "accepts `#{t}` inside `instance_eval` if it is called on a class other than Kernel" do
      expect_no_offenses <<~RUBY
        class Dummy
          def #{t}; end
        end

        d = Dummy.new
        d.instance_eval do
          Dummy.#{t}
          foo
        end
      RUBY
    end
  end
end
