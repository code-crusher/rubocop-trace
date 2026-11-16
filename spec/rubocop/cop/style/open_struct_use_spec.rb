# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Style::OpenStructUse, :config do
  context 'when using OpenStruct' do
    ['OpenStruct', '::OpenStruct'].each do |klass|
      context "for #{klass}" do
        context 'when used in assignments' do
          it 'registers an offense' do
            expect_offense(<<~RUBY, klass: klass)
              a = %{klass}.new(a: 42)
                  ^{klass} Avoid using `OpenStruct`;[...]
            RUBY
          end
        end

        context 'when inheriting from it via <' do
          it 'registers an offense' do
            expect_offense(<<~RUBY, klass: klass)
              class SubClass < %{klass}
                               ^{klass} Avoid using `OpenStruct`;[...]
              end
            RUBY
          end
        end

        context 'when inheriting from it via Class.new' do
          it 'registers an offense' do
            expect_offense(<<~RUBY, klass: klass)
              SubClass = Class.new(%{klass})
                                   ^{klass} Avoid using `OpenStruct`;[...]
            RUBY
          end
        end
      end
    end
  end

  context 'when using custom namespaced OpenStruct' do
    context 'when inheriting from it' do
      specify { expect_no_offenses('class A < SomeNamespace::OpenStruct; end') }
    end

    context 'when defined in custom namespace' do
      context 'when class' do
        specify do
          expect_no_offenses(<<~RUBY)
            module SomeNamespace
              class OpenStruct
              end
            end
          RUBY
        end
      end

      context 'when module' do
        specify do
          expect_no_offenses(<<~RUBY)
            module SomeNamespace
              module OpenStruct
              end
            end
          RUBY
        end
      end
    end

    context 'when used in assignments' do
      it 'registers no offense' do
        expect_no_offenses(<<~RUBY)
          a = SomeNamespace::OpenStruct.new
        RUBY
      end
    end
  end

  context 'when not using OpenStruct' do
    it 'registers no offense', :aggregate_failures do
      expect_no_offenses('class A < B; end')
      expect_no_offenses('a = 42')
    end
  end

  context 'when a bare `OpenStruct` constant is the root node' do
    it 'registers an offense without crashing' do
      expect_offense(<<~RUBY)
        OpenStruct
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY
    end
  end

  context 'when target Ruby version is 3.2 or higher', :ruby32 do
    it 'corrects `OpenStruct.new` with keyword arguments to `Data.define(...).new(...)`' do
      expect_offense(<<~RUBY)
        point = OpenStruct.new(x: 0, y: 1)
                ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_correction(<<~RUBY)
        point = Data.define(:x, :y).new(0, 1)
      RUBY
    end

    it 'corrects `::OpenStruct.new` to `::Data.define(...).new(...)`' do
      expect_offense(<<~RUBY)
        point = ::OpenStruct.new(x: 0)
                ^^^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_correction(<<~RUBY)
        point = ::Data.define(:x).new(0)
      RUBY
    end

    it 'corrects a call without parentheses' do
      expect_offense(<<~RUBY)
        point = OpenStruct.new x: 0, y: 1
                ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_correction(<<~RUBY)
        point = Data.define(:x, :y).new(0, 1)
      RUBY
    end

    it 'corrects a call that is part of a method chain' do
      expect_offense(<<~RUBY)
        OpenStruct.new(x: 0).to_h
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_correction(<<~RUBY)
        Data.define(:x).new(0).to_h
      RUBY
    end

    it 'corrects a call spanning several lines' do
      expect_offense(<<~RUBY)
        OpenStruct.new(
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
          x: 0,
          y: 1
        )
      RUBY

      expect_correction(<<~RUBY)
        Data.define(:x, :y).new(
          0,
          1
        )
      RUBY
    end

    it 'corrects a call with a braced hash argument' do
      expect_offense(<<~RUBY)
        OpenStruct.new({ x: 0 })
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_correction(<<~RUBY)
        Data.define(:x).new(0)
      RUBY
    end

    it 'corrects a call with member names ending in `?` or `!`' do
      expect_offense(<<~RUBY)
        OpenStruct.new(valid?: true, save!: false)
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_correction(<<~RUBY)
        Data.define(:valid?, :save!).new(true, false)
      RUBY
    end

    it 'corrects a call whose values contain method calls and heredocs' do
      expect_offense(<<~RUBY)
        OpenStruct.new(a: foo(1, 2), b: <<~TEXT)
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
          hi
        TEXT
      RUBY

      expect_correction(<<~RUBY)
        Data.define(:a, :b).new(foo(1, 2), <<~TEXT)
          hi
        TEXT
      RUBY
    end

    it 'corrects nested calls from the inside out' do
      expect_offense(<<~RUBY)
        OpenStruct.new(a: OpenStruct.new(b: 2))
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
                          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_correction(<<~RUBY)
        Data.define(:a).new(Data.define(:b).new(2))
      RUBY
    end

    it 'keeps a trailing comment on the same line' do
      expect_offense(<<~RUBY)
        OpenStruct.new(x: 0) # keep me
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_correction(<<~RUBY)
        Data.define(:x).new(0) # keep me
      RUBY
    end

    it 'keeps comments inside the arguments and the original layout' do
      expect_offense(<<~RUBY)
        OpenStruct.new(
        ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
          # the coordinates
          x: 0,
          y: 1
        )
      RUBY

      expect_correction(<<~RUBY)
        Data.define(:x, :y).new(
          # the coordinates
          0,
          1
        )
      RUBY
    end

    context 'when the arguments cannot be converted' do
      it 'does not correct a call without arguments' do
        expect_offense(<<~RUBY)
          OpenStruct.new
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with an empty hash' do
        expect_offense(<<~RUBY)
          OpenStruct.new({})
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with a non-literal argument' do
        expect_offense(<<~RUBY)
          OpenStruct.new(attributes)
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with a double splat' do
        expect_offense(<<~RUBY)
          OpenStruct.new(x: 0, **attributes)
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with a string key' do
        expect_offense(<<~RUBY)
          OpenStruct.new('x' => 0)
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with a duplicated key' do
        expect_offense(<<~RUBY)
          OpenStruct.new(x: 0, x: 1)
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with an invalid member name' do
        expect_offense(<<~RUBY)
          OpenStruct.new('a b': 0)
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with a block' do
        expect_offense(<<~RUBY)
          OpenStruct.new(x: 0) { |ostruct| ostruct.x }
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with a comment between a key and its value' do
        expect_offense(<<~RUBY)
          OpenStruct.new(
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
            x: # the x coordinate
              0
          )
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with a braced hash holding a comment' do
        expect_offense(<<~RUBY)
          OpenStruct.new({ x: 0 # the x coordinate
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
          })
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call without parentheses holding a comment' do
        expect_offense(<<~RUBY)
          OpenStruct.new x: 0, # the x coordinate
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
                        y: 1
        RUBY

        expect_no_corrections
      end

      it 'does not correct a call with safe navigation' do
        expect_offense(<<~RUBY)
          OpenStruct&.new(x: 0)
          ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
        RUBY

        expect_no_corrections
      end
    end
  end

  context 'when target Ruby version is lower than 3.2', :ruby31, unsupported_on: :prism do
    it 'registers an offense but does not correct' do
      expect_offense(<<~RUBY)
        point = OpenStruct.new(x: 0, y: 1)
                ^^^^^^^^^^ Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.
      RUBY

      expect_no_corrections
    end
  end
end
