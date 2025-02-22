require "spec"
require "spec/helpers/iterate"
require "../support/string"

private class BadSortingClass
  include Comparable(self)

  def <=>(other)
    1
  end
end

private class Spaceship
  getter value : Float64

  def initialize(@value : Float64, @return_nil = false)
  end

  def <=>(other : Spaceship)
    return nil if @return_nil

    value <=> other.value
  end
end

private def is_stable_sort(mutable, &block)
  n = 42
  # [Spaceship.new(0), ..., Spaceship.new(n - 1), Spaceship.new(0), ..., Spaceship.new(n - 1)]
  slice = Slice.new(n * 2) { |i| Spaceship.new((i % n).to_f) }
  # [Spaceship.new(0), Spaceship.new(0), ..., Spaceship.new(n - 1), Spaceship.new(n - 1)]
  expected = Slice.new(n * 2) { |i| slice[i % 2 * n + i // 2] }

  if mutable
    yield slice
    result = slice
  else
    result = yield slice
    result.should_not eq(slice)
  end

  result.size.should eq(expected.size)
  expected.zip(result) do |exp, res|
    res.should be(exp) # reference-equality is necessary to check sorting is stable.
  end
end

describe "Slice" do
  it "gets pointer and size" do
    pointer = Pointer.malloc(1, 0)
    slice = Slice.new(pointer, 1)
    slice.to_unsafe.should eq(pointer)
    slice.size.should eq(1)
  end

  it "does []?" do
    slice = Slice.new(3) { |i| i + 1 }
    3.times do |i|
      slice[i]?.should eq(i + 1)
    end
    slice[-1]?.should eq(3)
    slice[-2]?.should eq(2)
    slice[-3]?.should eq(1)

    slice[-4]?.should be_nil
    slice[3]?.should be_nil
  end

  it "does []" do
    slice = Slice.new(3) { |i| i + 1 }
    3.times do |i|
      slice[i].should eq(i + 1)
    end
    slice[-1].should eq(3)
    slice[-2].should eq(2)
    slice[-3].should eq(1)

    expect_raises(IndexError) { slice[-4] }
    expect_raises(IndexError) { slice[3] }
  end

  it "does []=" do
    slice = Slice.new(3, 0)
    slice[0] = 1
    slice[0].should eq(1)

    expect_raises(IndexError) { slice[-4] = 1 }
    expect_raises(IndexError) { slice[3] = 1 }
  end

  it "does +" do
    slice = Slice.new(3) { |i| i + 1 }

    slice1 = slice + 1
    slice1.size.should eq(2)
    slice1[0].should eq(2)
    slice1[1].should eq(3)

    slice3 = slice + 3
    slice3.size.should eq(0)

    expect_raises(IndexError) { slice + 4 }
    expect_raises(IndexError) { slice + (-1) }
  end

  it "does []? with start and count" do
    slice = Slice.new(4) { |i| i + 1 }
    slice1 = slice[1, 2]?
    slice1.should_not be_nil
    slice1 = slice1.not_nil!
    slice1.size.should eq(2)
    slice1[0].should eq(2)
    slice1[1].should eq(3)

    slice[-1, 1]?.should be_nil
    slice[3, 2]?.should be_nil
    slice[0, 5]?.should be_nil
    slice[3, -1]?.should be_nil
  end

  it "does [] with start and count" do
    slice = Slice.new(4) { |i| i + 1 }
    slice1 = slice[1, 2]
    slice1.size.should eq(2)
    slice1[0].should eq(2)
    slice1[1].should eq(3)

    expect_raises(IndexError) { slice[-1, 1] }
    expect_raises(IndexError) { slice[3, 2] }
    expect_raises(IndexError) { slice[0, 5] }
    expect_raises(IndexError) { slice[3, -1] }
  end

  it "does empty?" do
    Slice.new(0, 0).empty?.should be_true
    Slice.new(1, 0).empty?.should be_false
  end

  it "raises if size is negative on new" do
    expect_raises(ArgumentError) { Slice.new(-1, 0) }
  end

  it "does to_s" do
    slice = Slice.new(4) { |i| i + 1 }
    slice.to_s.should eq("Slice[1, 2, 3, 4]")
  end

  it "does to_s for bytes" do
    slice = Bytes[1, 2, 3]
    slice.to_s.should eq("Bytes[1, 2, 3]")
  end

  describe "#fill" do
    it "replaces all values, without block" do
      slice = Slice.new(4) { |i| i + 1 }
      expected = Slice.new(4, 7)
      slice.fill(7).should eq(expected)
      slice.should eq(expected)

      expected = Slice.new(4, 5)
      slice.fill(5).should eq(expected)
      slice.should eq(expected)
    end

    it "works with primitive number types and 0" do
      slice = Slice.new(4) { |i| i + 1 }
      expected = Slice.new(4, 0)
      slice.fill(0).should eq(expected)
      slice.should eq(expected)

      slice = Slice.new(4, &.to_f64)
      expected = Slice.new(4, 0.0)
      slice.fill(0.0).should eq(expected)
      slice.should eq(expected)

      slice = Slice.new(4, &.to_u8)
      expected = Slice.new(4, 0_u8)
      slice.fill(0).should eq(expected)
      slice.should eq(expected)
    end

    it "works with Bytes" do
      slice = Bytes[1, 2, 3]
      expected = Slice.new(3, 7_u8)
      slice.fill(7).should eq(expected)
      slice.should eq(expected)
    end

    it "replaces all values, with block" do
      slice = Slice.new(4) { |i| i + 1 }
      expected = Slice[0, 1, 4, 9]
      slice.fill { |i| i * i }.should eq(expected)
      slice.should eq(expected)
    end

    it "replaces all values, with block and offset" do
      slice = Slice.new(4) { |i| i + 1 }
      expected = Slice[9, 16, 25, 36]
      slice.fill(offset: 3) { |i| i * i }.should eq(expected)
      slice.should eq(expected)
    end
  end

  it "does copy_from pointer" do
    pointer = Pointer.malloc(4) { |i| i + 1 }
    slice = Slice.new(4, 0)
    slice.copy_from(pointer, 4)
    4.times { |i| slice[i].should eq(i + 1) }

    expect_raises(IndexError) { slice.copy_from(pointer, 5) }
  end

  it "does copy_to pointer" do
    pointer = Pointer.malloc(4, 0)
    slice = Slice.new(4) { |i| i + 1 }
    slice.copy_to(pointer, 4)
    4.times { |i| pointer[i].should eq(i + 1) }

    expect_raises(IndexError) { slice.copy_to(pointer, 5) }
  end

  describe ".copy_to(Slice)" do
    it "copies bytes" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(4) { 'b' }

      src.copy_to(dst)
      dst.should eq(src)
    end

    it "raises if dst is smaller" do
      src = Slice.new(8) { 'a' }
      dst = Slice.new(4) { 'b' }

      expect_raises(IndexError) { src.copy_to(dst) }
    end

    it "copies at most src.size" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(8) { 'b' }

      src.copy_to(dst)
      dst.should eq(Slice['a', 'a', 'a', 'a', 'b', 'b', 'b', 'b'])
    end
  end

  describe ".copy_from(Slice)" do
    it "copies bytes" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(4) { 'b' }

      dst.copy_from(src)
      dst.should eq(src)
    end

    it "raises if dst is smaller" do
      src = Slice.new(8) { 'a' }
      dst = Slice.new(4) { 'b' }

      expect_raises(IndexError) { dst.copy_from(src) }
    end

    it "copies at most src.size" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(8) { 'b' }

      dst.copy_from(src)
      dst.should eq(Slice['a', 'a', 'a', 'a', 'b', 'b', 'b', 'b'])
    end
  end

  describe ".move_to(Slice)" do
    it "moves bytes" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(4) { 'b' }

      src.move_to(dst)
      dst.should eq(src)
    end

    it "raises if dst is smaller" do
      src = Slice.new(8) { 'a' }
      dst = Slice.new(4) { 'b' }

      expect_raises(IndexError) { src.move_to(dst) }
    end

    it "moves most src.size" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(8) { 'b' }

      src.move_to(dst)
      dst.should eq(Slice['a', 'a', 'a', 'a', 'b', 'b', 'b', 'b'])
    end

    it "handles intersecting ranges" do
      # Test with ranges offset by 0 to 8 bytes
      (0..8).each do |offset|
        buf = Slice.new(16) { |i| 'a' + i }
        dst = buf[0, 8]
        src = buf[offset, 8]

        src.move_to(dst)

        result = (0..7).map { |i| 'a' + i + offset }
        dst.should eq(Slice.new(result.to_unsafe, result.size))
      end
    end
  end

  describe ".move_from(Slice)" do
    it "moves bytes" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(4) { 'b' }

      dst.move_from(src)
      dst.should eq(src)
    end

    it "raises if dst is smaller" do
      src = Slice.new(8) { 'a' }
      dst = Slice.new(4) { 'b' }

      expect_raises(IndexError) { dst.move_from(src) }
    end

    it "moves at most src.size" do
      src = Slice.new(4) { 'a' }
      dst = Slice.new(8) { 'b' }

      dst.move_from(src)
      dst.should eq(Slice['a', 'a', 'a', 'a', 'b', 'b', 'b', 'b'])
    end

    it "handles intersecting ranges" do
      # Test with ranges offset by 0 to 8 bytes
      (0..8).each do |offset|
        buf = Slice.new(16) { |i| 'a' + i }
        dst = buf[0, 8]
        src = buf[offset, 8]

        dst.move_from(src)

        result = (0..7).map { |i| 'a' + i + offset }
        dst.should eq(Slice.new(result.to_unsafe, result.size))
      end
    end
  end

  it "does hexstring" do
    slice = Bytes.new(4) { |i| i.to_u8 + 1 }
    slice.hexstring.should eq("01020304")
  end

  it "does hexdump for empty slice" do
    Bytes.empty.hexdump.should eq("")

    io = IO::Memory.new
    Bytes.empty.hexdump(io).should eq(0)
    io.to_s.should eq("")
  end

  it "does hexdump" do
    slice = Bytes.new(96) { |i| i.to_u8 + 32 }
    assert_prints slice.hexdump, <<-EOF
      00000000  20 21 22 23 24 25 26 27  28 29 2a 2b 2c 2d 2e 2f   !"#$%&'()*+,-./
      00000010  30 31 32 33 34 35 36 37  38 39 3a 3b 3c 3d 3e 3f  0123456789:;<=>?
      00000020  40 41 42 43 44 45 46 47  48 49 4a 4b 4c 4d 4e 4f  @ABCDEFGHIJKLMNO
      00000030  50 51 52 53 54 55 56 57  58 59 5a 5b 5c 5d 5e 5f  PQRSTUVWXYZ[\\]^_
      00000040  60 61 62 63 64 65 66 67  68 69 6a 6b 6c 6d 6e 6f  `abcdefghijklmno
      00000050  70 71 72 73 74 75 76 77  78 79 7a 7b 7c 7d 7e 7f  pqrstuvwxyz{|}~.\n
      EOF

    plus = Bytes.new(101) { |i| i.to_u8 + 32 }
    assert_prints plus.hexdump, <<-EOF
      00000000  20 21 22 23 24 25 26 27  28 29 2a 2b 2c 2d 2e 2f   !"#$%&'()*+,-./
      00000010  30 31 32 33 34 35 36 37  38 39 3a 3b 3c 3d 3e 3f  0123456789:;<=>?
      00000020  40 41 42 43 44 45 46 47  48 49 4a 4b 4c 4d 4e 4f  @ABCDEFGHIJKLMNO
      00000030  50 51 52 53 54 55 56 57  58 59 5a 5b 5c 5d 5e 5f  PQRSTUVWXYZ[\\]^_
      00000040  60 61 62 63 64 65 66 67  68 69 6a 6b 6c 6d 6e 6f  `abcdefghijklmno
      00000050  70 71 72 73 74 75 76 77  78 79 7a 7b 7c 7d 7e 7f  pqrstuvwxyz{|}~.
      00000060  80 81 82 83 84                                    .....\n
      EOF

    num = Bytes.new(10) { |i| i.to_u8 + 48 }
    assert_prints num.hexdump, <<-EOF
      00000000  30 31 32 33 34 35 36 37  38 39                    0123456789\n
      EOF
  end

  it_iterates "#each", [1, 2, 3], Slice[1, 2, 3].each
  it_iterates "#reverse_each", [3, 2, 1], Slice[1, 2, 3].reverse_each
  it_iterates "#each_index", [0, 1, 2], Slice[1, 2, 3].each_index

  it "does to_a" do
    slice = Slice.new(3) { |i| i }
    ary = slice.to_a
    ary.should eq([0, 1, 2])
  end

  it "does rindex" do
    slice = "foobar".to_slice
    slice.rindex('o'.ord.to_u8).should eq(2)
    slice.rindex('z'.ord.to_u8).should be_nil
  end

  it "does bytesize" do
    slice = Slice(Int32).new(2)
    slice.bytesize.should eq(8)
  end

  describe "==" do
    it "does ==" do
      a = Slice.new(3) { |i| i }
      b = Slice.new(3) { |i| i }
      c = Slice.new(3) { |i| i + 1 }
      a.should eq(b)
      a.should_not eq(c)
    end

    it "does == with same type, different runtime instances" do
      a = Slice.new(3, &.to_s)
      b = Slice.new(3, &.to_s)
      a.should eq(b)
    end

    it "does == for bytes" do
      a = Bytes[1, 2, 3]
      b = Bytes[1, 2, 3]
      c = Bytes[1, 2, 4]
      a.should eq(b)
      a.should_not eq(c)
    end
  end

  it "does macro []" do
    slice = Slice[1, 'a', "foo"]
    slice.should be_a(Slice(Int32 | Char | String))
    slice.size.should eq(3)
    slice[0].should eq(1)
    slice[1].should eq('a')
    slice[2].should eq("foo")
  end

  it "does macro [] with numbers (#3055)" do
    slice = Bytes[1, 2, 3]
    slice.should be_a(Bytes)
    slice.to_a.should eq([1, 2, 3])
  end

  it "uses percent vars in [] macro (#2954)" do
    slices = itself(Slice[1, 2], Slice[3])
    slices[0].to_a.should eq([1, 2])
    slices[1].to_a.should eq([3])
  end

  it "reverses" do
    slice = Bytes[1, 2, 3]
    slice.reverse!
    slice.to_a.should eq([3, 2, 1])
  end

  it "shuffles" do
    a = Bytes[1, 2, 3]
    a.shuffle!
    b = [1, 2, 3]
    3.times { a.includes?(b.shift).should be_true }
  end

  it "does map" do
    a = Slice[1, 2, 3]
    b = a.map { |x| x * 2 }
    b.should eq(Slice[2, 4, 6])
  end

  it "does map!" do
    a = Slice[1, 2, 3]
    b = a.map! { |x| x * 2 }
    a.should eq(Slice[2, 4, 6])
    a.to_unsafe.should eq(b.to_unsafe)
  end

  it "does map_with_index" do
    a = Slice[1, 1, 2, 2]
    b = a.map_with_index { |e, i| e + i }
    b.should eq(Slice[1, 2, 4, 5])
  end

  it "does map_with_index, with offset" do
    a = Slice[1, 1, 2, 2]
    b = a.map_with_index(10) { |e, i| e + i }
    b.should eq(Slice[11, 12, 14, 15])
  end

  it "does map_with_index!" do
    a = Slice[1, 1, 2, 2]
    b = a.map_with_index! { |e, i| e + i }
    a.should eq(Slice[1, 2, 4, 5])
    a.to_unsafe.should eq(b.to_unsafe)
  end

  it "does map_with_index!, with offset" do
    a = Slice[1, 1, 2, 2]
    b = a.map_with_index!(10) { |e, i| e + i }
    a.should eq(Slice[11, 12, 14, 15])
    a.to_unsafe.should eq(b.to_unsafe)
  end

  describe "rotate!" do
    it do
      a = Slice[1, 2, 3]
      a.rotate!.to_unsafe.should eq(a.to_unsafe); a.should eq(Slice[2, 3, 1])
      a.rotate!.to_unsafe.should eq(a.to_unsafe); a.should eq(Slice[3, 1, 2])
      a.rotate!.to_unsafe.should eq(a.to_unsafe); a.should eq(Slice[1, 2, 3])
      a.rotate!.to_unsafe.should eq(a.to_unsafe); a.should eq(Slice[2, 3, 1])
    end

    it { a = Slice[1, 2, 3]; a.rotate!(0); a.should eq(Slice[1, 2, 3]) }
    it { a = Slice[1, 2, 3]; a.rotate!(1); a.should eq(Slice[2, 3, 1]) }
    it { a = Slice[1, 2, 3]; a.rotate!(2); a.should eq(Slice[3, 1, 2]) }
    it { a = Slice[1, 2, 3]; a.rotate!(3); a.should eq(Slice[1, 2, 3]) }
    it { a = Slice[1, 2, 3]; a.rotate!(4); a.should eq(Slice[2, 3, 1]) }
    it { a = Slice[1, 2, 3]; a.rotate!(3001); a.should eq(Slice[2, 3, 1]) }
    it { a = Slice[1, 2, 3]; a.rotate!(-1); a.should eq(Slice[3, 1, 2]) }
    it { a = Slice[1, 2, 3]; a.rotate!(-3001); a.should eq(Slice[3, 1, 2]) }

    it do
      a = Slice(Int32).new(50) { |i| i }
      a.rotate!(5)
      a.should eq(Slice[5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4])
    end

    it do
      a = Slice(Int32).new(50) { |i| i }
      a.rotate!(-5)
      a.should eq(Slice[45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44])
    end

    it do
      a = Slice(Int32).new(50) { |i| i }
      a.rotate!(20)
      a.should eq(Slice[20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19])
    end

    it do
      a = Slice(Int32).new(50) { |i| i }
      a.rotate!(-20)
      a.should eq(Slice[30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29])
    end
  end

  it "creates empty slice" do
    slice = Slice(Int32).empty
    slice.empty?.should be_true
  end

  it "creates read-only slice" do
    slice = Slice.new(3, 0, read_only: true)
    slice.read_only?.should be_true
    expect_raises(Exception, "Can't write to read-only Slice") { slice[0] = 1 }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.update(0, &.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.swap(0, 1) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.reverse! }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(0) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(&.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.fill(offset: 0, &.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.map!(&.itself) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.map_with_index! { |v, i| v } }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.map_with_index!(offset: 0) { |v, i| v } }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.shuffle! }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.rotate!(0) }
    expect_raises(Exception, "Can't write to read-only Slice") { slice.copy_from(slice) }

    subslice = slice[0, 1]
    subslice.read_only?.should be_true
    expect_raises(Exception, "Can't write to read-only Slice") { subslice[0] = 1 }

    slice = Bytes[1, 2, 3, read_only: true]
    slice.read_only?.should be_true
    expect_raises(Exception, "Can't write to read-only Slice") { slice[0] = 0_u8 }
  end

  it "hashes each item in collection" do
    Slice[1, 2, 3].hash.should eq(Slice[1_u64, 2_u64, 3_u64].hash)
  end

  it "optimizes hash for Bytes" do
    Bytes[1, 2, 3].hash.should_not eq(Slice[1, 2, 3].hash)
  end

  it "#[]" do
    slice = Slice.new(6) { |i| i + 1 }
    subslice = slice[2..4]
    subslice.read_only?.should be_false
    subslice.size.should eq(3)
    subslice.should eq(Slice.new(3) { |i| i + 3 })
  end

  it "#[] keeps read-only value" do
    slice = Slice.new(6, read_only: true) { |i| i + 1 }
    slice[2..4].read_only?.should be_true
  end

  describe "#clone" do
    it "clones primitive" do
      slice = Slice[1, 2]
      slice.clone.should eq slice
    end

    it "clones non-primitive" do
      slice = Slice["abc", "a"]
      slice.clone.should eq slice
    end

    it "buffer copy" do
      slice = Slice["foo"]
      copy = slice.clone
      slice[0] = "bar"
      copy.should_not eq slice
    end

    it "deep copy" do
      slice = Slice[["foo"]]
      copy = slice.clone
      slice[0] << "bar"
      copy.should_not eq slice
    end
  end

  describe "#dup" do
    it "buffer copy" do
      slice = Slice["foo"]
      copy = slice.dup
      slice[0] = "bar"
      copy.should_not eq slice
    end

    it "don't deep copy" do
      slice = Slice[["foo"]]
      copy = slice.dup
      slice[0] << "bar"
      copy.should eq slice
    end
  end

  describe "sort" do
    {% for sort in ["sort".id, "unstable_sort".id] %}
      describe {{ "##{sort}" }} do
        it "without block" do
          slice = Slice[3, 4, 1, 2, 5, 6]
          sorted_slice = slice.{{ sort }}
          sorted_slice.to_a.should eq([1, 2, 3, 4, 5, 6])
          slice.should_not eq(sorted_slice)
        end

        it "with a block" do
          a = Slice["foo", "a", "hello"]
          b = a.{{ sort }} { |x, y| x.size <=> y.size }
          b.to_a.should eq(["a", "foo", "hello"])
          a.should_not eq(b)
        end

        {% if sort == "sort" %}
          it "stable sort without a block" do
            is_stable_sort(mutable: false, &.sort)
          end

          it "stable sort with a block" do
            is_stable_sort(mutable: false, &.sort { |a, b| a.value <=> b.value })
          end
        {% end %}
      end

      describe {{ "##{sort}!" }} do
        it "without block" do
          a = [3, 4, 1, 2, 5, 6]
          a.{{ sort }}!
          a.should eq([1, 2, 3, 4, 5, 6])
        end

        it "with a block" do
          a = ["foo", "a", "hello"]
          a.{{ sort }}! { |x, y| x.size <=> y.size }
          a.should eq(["a", "foo", "hello"])
        end

        it "sorts with invalid block (#4379)" do
          a = [1] * 17
          b = a.{{ sort }} { -1 }
          a.should eq(b)
        end

        it "can sort! just by using <=> (#6608)" do
          spaceships = Slice[
            Spaceship.new(2),
            Spaceship.new(0),
            Spaceship.new(1),
            Spaceship.new(3),
          ]

          spaceships.{{ sort }}!
          4.times do |i|
            spaceships[i].value.should eq(i)
          end
        end

        it "raises if <=> returns nil" do
          spaceships = Slice[
            Spaceship.new(2, return_nil: true),
            Spaceship.new(0, return_nil: true),
          ]

          expect_raises(ArgumentError) do
            spaceships.{{ sort }}!
          end
        end

        it "raises if sort! block returns nil" do
          expect_raises(ArgumentError) do
            Slice[1, 2].{{ sort }}! { nil }
          end
        end

        {% if sort == "sort" %}
          it "stable sort without a block" do
            is_stable_sort(mutable: true, &.sort!)
          end

          it "stable sort with a block" do
            is_stable_sort(mutable: true, &.sort! { |a, b| a.value <=> b.value })
          end
        {% end %}
      end

      describe {{ "##{sort}_by" }} do
        it "sorts" do
          a = Slice["foo", "a", "hello"]
          b = a.{{ sort }}_by(&.size)
          b.to_a.should eq(["a", "foo", "hello"])
          a.should_not eq(b)
        end

        {% if sort == "sort" %}
          it "stable sort" do
            is_stable_sort(mutable: false, &.sort_by(&.value))
          end
        {% end %}
      end

      describe {{ "##{sort}_by" }} do
        it "sorts" do
          a = Slice["foo", "a", "hello"]
          a.{{ sort }}_by!(&.size)
          a.to_a.should eq(["a", "foo", "hello"])
        end

        it "calls given block exactly once for each element" do
          calls = Hash(String, Int32).new(0)
          a = Slice["foo", "a", "hello"]
          a.{{ sort }}_by! { |e| calls[e] += 1; e.size }
          calls.should eq({"foo" => 1, "a" => 1, "hello" => 1})
        end

        {% if sort == "sort" %}
          it "stable sort" do
            is_stable_sort(mutable: true, &.sort_by!(&.value))
          end
        {% end %}
      end
    {% end %}
  end

  describe "<=>" do
    it "is comparable" do
      Bytes[1].is_a?(Comparable).should be_true
    end

    it "compares" do
      (Int32.slice(1, 2, 3) <=> Int32.slice(1, 2, 3)).should eq(0)
      (Int32.slice(1, 2, 3) <=> Int32.slice(1, 3, 3)).should be < 0
      (Int32.slice(1, 3, 3) <=> Int32.slice(1, 2, 3)).should be > 0
      (Int32.slice(1, 2, 3) <=> Int32.slice(1, 2, 3, 4)).should be < 0
      (Int32.slice(1, 2, 3, 4) <=> Int32.slice(1, 2, 3)).should be > 0
    end

    it "compares (UInt8)" do
      (Bytes[1, 2, 3] <=> Bytes[1, 2, 3]).should eq(0)
      (Bytes[1, 2, 3] <=> Bytes[1, 3, 3]).should be < 0
      (Bytes[1, 3, 3] <=> Bytes[1, 2, 3]).should be > 0
      (Bytes[1, 2, 3] <=> Bytes[1, 2, 3, 4]).should be < 0
      (Bytes[1, 2, 3, 4] <=> Bytes[1, 2, 3]).should be > 0
    end
  end
end

private def itself(*args)
  args
end
