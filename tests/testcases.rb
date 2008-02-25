class TC_MyTest < Test::Unit::TestCase

   DO_TEST = :test_split_single_horiz

   def test_split_single_horiz
      # this is a :sp, as in a horizontal bar splitting the buffer
      before = TextWithCursor.new(%{
        X
      X this is a stupid little silly test see! :)}, "rb")
      $myedteststub.do_rendering {
         buf = reset_create_and_switch_to
         buf.lines = before.buffer_lines
         send_cmd ":sp\r"
         check_rendering buf, "split_single_horiz"
      }
   end

   def test_part_word_movement
      do_test_case %{
        X
      X blah_part_word_movement a blah another_long_one another normal a_long_one}, "zl", %{
             X
      X blah_part_word_movement a blah another_long_one another normal a_long_one}, "WWWWzhdzh$Bzldzl", %{
                                                                    X
      X blah_part_word_movement a blah another_one another normal a_one}, "0zlczl", %{
             X
      X blah__word_movement a blah another_one another normal a_one}, "BLUB\e", %{
                 X
      X blah_BLUB_word_movement a blah another_one another normal a_one}, "czhblah\e", %{
                 X
      X blah_blah_word_movement a blah another_one another normal a_one}, "lczhglug_\e", %{
                  X
      X blah_glug_word_movement a blah another_one another normal a_one}
   end

   def test_goto_eol
      do_test_case %{
               X
      X i am not really here}, "$", %{
                           X
      X i am not really here}
   end

   def do_movement_in_empty_buffer_test buf
      send_cmd "h"
      assert_equal [0, 0], [buf.x, buf.y]
      send_cmd "l"
      assert_equal [0, 0], [buf.x, buf.y]
      send_cmd "j"
      assert_equal [0, 0], [buf.x, buf.y]
      send_cmd "k"
      assert_equal [0, 0], [buf.x, buf.y]
   end

   def test_skip_paragraph
      before = TextWithCursor.new(%{
        X
      X 
        above is to test jump onto first line, and implicitly first if similar code used
        
        this test is to test basic behaviour
        
        this test checks that spaces are start of line still count as empty line
           
          this test has whitespace at start, just for the heck of it :)
        of its also multi line

        this test it to show that it ends at eof && eol}, "rb")
      buf = reset_create_and_switch_to
      buf.fname = "textfile"
      buf.lines = before.buffer_lines
      buf.x, buf.y = 0, 0
      send_cmd "}"; assert_equal [0, 2],  [buf.x, buf.y]
      send_cmd "}"; assert_equal [0, 4],  [buf.x, buf.y]
      send_cmd "}"; assert_equal [0, 6],  [buf.x, buf.y]
      send_cmd "}"; assert_equal [0, 9],  [buf.x, buf.y]
      send_cmd "}"; assert_equal [46, 10], [buf.x, buf.y]
      send_cmd "}"; assert_equal [0, 0],  [buf.x, buf.y]
      send_cmd "}"; assert_equal [0, 2],  [buf.x, buf.y]
      send_cmd "{"; assert_equal [0, 0],  [buf.x, buf.y]
      send_cmd "{"; assert_equal [0, 10], [buf.x, buf.y]
      send_cmd "{"; assert_equal [0, 9],  [buf.x, buf.y]
      send_cmd "{"; assert_equal [0, 6],  [buf.x, buf.y]
      send_cmd "{"; assert_equal [0, 4],  [buf.x, buf.y]
      send_cmd "{"; assert_equal [0, 2],  [buf.x, buf.y]
      send_cmd "{"; assert_equal [0, 0],  [buf.x, buf.y]
      send_cmd "{"; assert_equal [0, 10], [buf.x, buf.y]
   end

   def test_match
      before = TextWithCursor.new(%{
        X
      X while true
         if blah(a, b, c)
           5.times {
              blub { 5 }
           }
         end
        end}, "rb")
      buf = reset_create_and_switch_to
      buf.fname = "blub.rb"
      buf.lines = before.buffer_lines
      buf.x, buf.y = 1, 1; send_cmd "%"
      assert_equal [1, 5], [buf.x, buf.y]; send_cmd "%"; assert_equal [1, 1], [buf.x, buf.y]
      buf.x, buf.y = 0, 0; send_cmd "%"
      assert_equal [0, 6], [buf.x, buf.y]; send_cmd "%"; assert_equal [0, 0], [buf.x, buf.y]
      buf.x, buf.y = 11, 3; send_cmd "%"
      assert_equal [15, 3], [buf.x, buf.y]; send_cmd "%"; assert_equal [11, 3], [buf.x, buf.y]
      buf.x, buf.y = 11, 2; send_cmd "%"
      assert_equal [3, 4], [buf.x, buf.y]; send_cmd "%"; assert_equal [11, 2], [buf.x, buf.y]
   end

   def test_hjkl
      buf = reset_create_and_switch_to
      # first perform test on buffer with single empty line
      do_movement_in_empty_buffer_test buf
      # moving onto/on an empty line bug
      do_test_case %{
            X
      X line 1
        
        line 3}, "j", %{    # moving onto
        X
        line 1
      X 
        line 3}, "l", %{    # moving within
        X
        line 1
      X 
        line 3}, "k$j", %{ # moving onto but in end_char_mode
        X
        line 1
      X 
        line 3}
      # generic movement tests
      do_test_case %{
        X
      X line 1
        line 2
        line 3}, "l", %{   # single right, no wrap
         X
      X line 1
        line 2
        line 3}, "2l", %{  # multi right, no wrap
           X
      X line 1
        line 2
        line 3}, "2j", %{  # multi down, no wrap
           X
        line 1
        line 2
      X line 3}, "j", %{   # vert wrap from last to first line
           X
      X line 1
        line 2
        line 3}, "k", %{   # vert wrap back from first to last
           X
        line 1
        line 2
      X line 3}, "k", %{   # single up, no wrap
           X
        line 1
      X line 2
        line 3}, "h", %{   # single left, no wrap
          X
        line 1
      X line 2
        line 3}, "jlll", %{ # move single down and rights to last char in document (implicitly last char in any line is tested also)
             X
        line 1
        line 2
      X line 3}, "l", %{   # wrap to from last to first char in document
        X     
      X line 1
        line 2
        line 3}, "h", %{   # wrap to last to first char in document
             X
        line 1
        line 2
      X line 3}, "ll", %{  # wrap to first char and then a simple right - paranoid test case :)
         X
      X line 1
        line 2
        line 3}, "4l", %{  # movement to end of first line via multi right
             X
      X line 1
        line 2
        line 3}, "l", %{  # wrap to start of next line via simple right from end
        X
        line 1
      X line 2
        line 3}, "h", %{  # wrap to end of last line via simple left from end
             X
      X line 1
        line 2
        line 3}
      # summary : normal moves, vert and horiz wraps between first/last char in doc, and first/last char in lines
   end

   def test_word_movements
      do_test_case %{
        X
      X }, "b", %{
        X
      X }, "w", %{
        X
      X }
      do_test_case %{
            X
      X i am not really here}, "w", %{
             X
      X i am not really here}, "w", %{
                 X
      X i am not really here}, "b", %{
             X
      X i am not really here}
   end

   def test_delete_word
      do_test_case %{
             X
      X i am not really here}, "de", %{
             X
      X i am  really here}
      do_test_case %{
             X
      X i am not really here}, "dw", %{
             X
      X i am really here}
      do_test_case %{
        X
      X    i am not really here}, "dw", %{
        X
      X i am not really here}
   end

   def test_change_word
      do_test_case %{
                 X 
      X i am not really here}, "cwblah\e", %{
                     X
      X i am not blah here}, "b\e", %{
                 X
      X i am not blah here}, "whcbblub\e", %{
                     X
      X i am not blub here}, "$bcwwhat\e", %{
                         X
      X i am not blub what}
   end

   def test_replace_modes
      do_test_case %{
                 X 
      X i am not blah here}, "rB", %{
                 X
      X i am not Blah here}
      do_test_case %{
                 X 
      X i am not blah here}, "RWORD\e", %{
                     X
      X i am not WORD here}
   end

   def test_join_line
      do_test_case %{
        X
      X this is a test line
        this is the bit that will be joined :)}, "J", %{
                           X
      X this is a test line this is the bit that will be joined :)}
      do_test_case %{
        X
      X this is a test line
           this is the bit that will be joined :)}, "J", %{
                           X
      X this is a test line this is the bit that will be joined :)}
   end

   def test_position_after_escape
      do_test_case %{
        X 
      X}, "iblah blah blah?\e", %{
                      X
      X blah blah blah?}, "i who?\e", %{
                           X
      X blah blah blah who??}
   end

   def test_text_backspace
      do_test_case %{
        X 
      X}, "iblah blah blah?\e", %{
                      X
      X blah blah blah?}, "A who?\b\b\b\bwhat?\e", %{
                            X
      X blah blah blah? what?}
      assert_equal "4", @app.settings[:sw]
      do_test_case %{
        X 
      X }, "i   \bblah", %{
           X
      X blah}
      do_test_case %{
        X 
      X }, "i\b\b\b\b\b\b\b\b", %{
        X
      X }
      do_test_case %{
        X 
      X }, "i\ttab test!", %{
                    X
      X     tab test!}
      do_test_case %{
        X 
      X }, ":set sw=3\ri\ttab test!", %{
                   X
      X    tab test!}
      do_test_case %{
        X 
      X line one
        line two
        line three}, "GA" + ("\b" * ("\n" + "line two\n" + "line three").length), %{
               X
      X line one}
   end

   def test_insert_modes # doesn't include c based commands
      # line based - O, o, S and strangely, i which should really be below
      do_test_case %{
        X 
      X}, "i2\eo3\ekO1\ejjo4\e", %{
        X
        1
        2
        3
      X 4}, "S5\e", %{
        X
        1
        2
        3
      X 5}
      # character based - a, A, I
      do_test_case %{
        X 
      X 3}, "A45\e", %{
          X
      X 345}, "I12\e", %{
          X
      X 12345}, "jjaWORD\e", %{
               X
      X 123WORD45}
   end

   def test_buffer_creation
      do_test_case %{
        X
      X buffer 1 text}, ":new\ribuffer 2 text\e:new\ribuffer 3 text\e:b1\r", %{
        X
      X buffer 1 text}, ":b2\r^", %{
        X
      X buffer 2 text}, ":b3\r^", %{
        X
      X buffer 3 text}
   end

   def test_function_chooser
      # NOTE - buffers are numbered 3+ for the moment, but this could change!
      buffer = <<EOB
module Outer
   class Inner
      def func_with_no_param
         # line 5
      end
      def func_with_params param, param_two
         # line 8
      end
      def func_with_complex_params param = 5, p, *k
         # line 11
      end
      module InnerInner
         def InnerInner.big_function
            # line 12
         end
      end
   end
end
EOB
      buf = reset_create_and_switch_to
      buf.fname = "test.rb"
      buf.lines = buffer.split("\n").collect { |l| BufferLine.new l }
      send_cmd "\C-x\C-c"
      assert_equal(
"[:0] Outer
[:1] Outer::Inner
[:2] Outer::Inner::func_with_no_param
[:5] Outer::Inner::func_with_params
[:8] Outer::Inner::func_with_complex_params
[:11] Outer::Inner::InnerInner
[:12] Outer::Inner::InnerInner::InnerInner.big_function", @app.current_buffer.text)
      send_cmd ":b1\r"
      send_cmd "\C-x\C-c/func_with_no_param\r\r"
      assert_equal 2, buf.y
      send_cmd "\C-x\C-c/func_with_params\r\r"
      assert_equal 5, buf.y
      send_cmd "\C-x\C-c/func_with_complex_params\r\r"
      assert_equal 8, buf.y
      send_cmd "\C-x\C-c/big_function\r\r"
      assert_equal 12, buf.y
   end

   def test_line_movement_scrolling
      buf = reset_create_and_switch_to
      30.times { buf.lines << BufferLine.new }
      send_cmd "M"
      assert_equal 15, buf.y
      370.times { buf.lines << BufferLine.new }
      send_cmd ":300\r"
      assert_equal 299, buf.y
      send_cmd "300gg"
      assert_equal 299, buf.y
      send_cmd "L"
      assert_equal 346, buf.y
      send_cmd "H"
      assert_equal 299, buf.y
      send_cmd "k"
      assert_equal 298, buf.y
      299.times { send_cmd "k" }
      send_cmd "k"
      assert_equal 399, buf.y
      100.times { send_cmd "k" }
      assert_equal 299, buf.y
      send_cmd "gg"
      assert_equal 0, buf.y
      400.times { send_cmd "j" }
      assert_equal 400, buf.y
      send_cmd "j"
      assert_equal 0, buf.y
   end

   def test_clamp_to
      assert_equal(0,   -50.clamp_to(0, 150))   # +ve clamps, by bottom
      assert_equal(150, 200.clamp_to(0, 150))   # +ve clamps, by top
      assert_equal(150, 150.clamp_to(0, 150))   # +ve clamps, equal to top
      assert_equal(0,     0.clamp_to(0, 150))   # +ve clamps, equal to bottom
      assert_equal(0,     0.clamp_to(0, 0))     # all 0's
      assert_equal(-20, -40.clamp_to(-20, 20))  # +/-ve clamps, by bottom
      assert_equal(-40, -60.clamp_to(-40, -20)) # -ve clamps, by top
   end

   def test_buffer_selector
      # NOTE - buffers are numbered 3+ for the moment, but this could change!
      do_test_case %{
        X
      X buffer 1 text}, ":new\ribuffer 2 text\e:new\ribuffer 3 text\e:b1\r\C-s/:b1\r\r^", %{
        X
      X buffer 1 text}, "\C-s/:b2\r\r^", %{
        X
      X buffer 2 text}, "\C-s/:b3\r\r^", %{
        X
      X buffer 3 text}
   end

   def test_goto_line
      buf = reset_create_and_switch_to
      400.times { buf.lines << BufferLine.new }
      send_cmd ":1\r"
      assert_equal(0, buf.y)
      assert_equal(0, buf.top) # TODO this is wrong..
      send_cmd ":400\r"
      assert_equal(399, buf.y)
      assert_equal(399, buf.top) # TODO this is wrong..
      send_cmd ":200\r"
      assert_equal(199, buf.y)
      assert_equal(199, buf.top) # TODO this is wrong..
      send_cmd "G"
      assert_equal(400, buf.y)
      send_cmd "50G"
      assert_equal(49, buf.y)
   end

   def test_quit
      reset_create_and_switch_to
      # create two buffers with edits and q! 
      send_cmd "iBLAH\e:new\riBLAH!\e:q!\r"
      assert !$was_closed
      assert_equal 2, @app.current_buffer.bnum
      assert_equal 2, @app.buffers_to_save.length
      assert_equal "more than one file unsaved! use :qa! to revert all!", @app.status_bar.text
      # repeat the q!
      send_cmd ":q!\r"
      assert !$was_closed
      assert_equal 2, @app.current_buffer.bnum
      assert_equal 2, @app.buffers_to_save.length
      assert_equal "more than one file unsaved! use :qa! to revert all!", @app.status_bar.text
      # revert the current buffer and use q!
      send_cmd "u:q!\r"
      assert !$was_closed
      assert_equal 1, @app.current_buffer.bnum
      assert_equal 1, @app.buffers_to_save.length
      # test that q with a modified buffer refuses to quit
      send_cmd ":q\r"
      assert !$was_closed
      assert_equal 1, @app.current_buffer.bnum
      assert_equal 1, @app.buffers_to_save.length
      send_cmd ":q!\r"
      # test that q! with a single modified buffer reverts and quits
      assert $was_closed
      reset_create_and_switch_to
      fname1 = make_tmpfname
      File.open(fname1, "w") { |f| f.puts "this is the first test line" }
      fname2 = make_tmpfname
      File.open(fname2, "w") { |f| f.puts "this is the first test line in the second file" }
      send_cmd ":ed #{fname1}\r:ed #{fname1}\r" # NOTE - for the moment. there are 3 buffers. a empty one. and two files
      assert_equal 3, @app.current_buffer.bnum
      assert_equal 3, @app.real_buffers.length
      send_cmd ":q\r"
      assert_equal 1, @app.current_buffer.bnum
      assert_equal 2, @app.real_buffers.length
      send_cmd ":q\r"
      assert_equal 2, @app.current_buffer.bnum
      assert_equal 1, @app.real_buffers.length
   end

   def test_adjust_indent
      do_test_case %{
        X
      X line one
         line two}, "vj<", %{
        X
        line one
      X line two}, ">", %{
        X
            line one
      X     line two}
   end

   def make_tmpfname 
      # TODO - use Tempfile
      "/tmp/ruvi-save-test.#{$$}.#{(0..8).collect{rand 10}.join ""}" # should be /tmp but this shows a unfixed bug in +.*.edlog
   end

   def test_save_all
      reset_create_and_switch_to
      fname1 = make_tmpfname
      File.open(fname1, "w") { |f| f.puts "this is the first test line" }
      send_cmd ":ed #{fname1}\r"
      fname2 = make_tmpfname
      File.open(fname2, "w") { |f| f.puts "this is the second test line" }
      send_cmd ":ed #{fname2}\r"
      send_cmd ":b2\rwwwcwnew-first\e"
      send_cmd ":b3\rwwwcwnew-second\e"
      send_cmd ":wa\r"
      content1 = File.open(fname1) { |f| f.gets nil }
      assert_equal content1, "this is the new-first test line\n"  # TODO - we need a test that checks that files without a ending \n are always left intact
      File.delete fname1
      content2 = File.open(fname2) { |f| f.gets nil }
      assert_equal content2, "this is the new-second test line\n"
      File.delete fname2
   end

   def test_save_unnamed
      buf = reset_create_and_switch_to
      send_cmd ":wq\r"
      assert !$was_closed
      assert_equal "ERROR - unnamed file on buffer 1", @app.status_bar.text
   end

   def test_switch_to_last_buffer
      buf = reset_create_and_switch_to
      send_cmd "ibuffer 1 text\e:new\ribuffer 2 text\e:new\ribuffer 3 text\e"
      send_cmd ":b1\r:b2\r\C-w"
      assert_equal "buffer 1 text", @app.current_buffer.text
      send_cmd ":b3\r:b1\r\C-w"
      assert_equal "buffer 3 text", @app.current_buffer.text
   end

   SELECTIONS_TEST = %{
     X
   X line 1
     line 2
     line 3}

   # all tests are via 
   def test_selections
      # delete block selection some lines shorter than selection
      do_test_case SELECTIONS_TEST, "GAblah\eh\C-vgg0d", %{
        X
      X 
        
        h}
      # block selection left to right upwards
      do_test_case SELECTIONS_TEST, "$j\C-vhhhkd", %{
         X
        li
      X li
        line 3}
      # block selection left to right downwards
      do_test_case SELECTIONS_TEST, "$\C-vhhhjd", %{
         X
        li
      X li
        line 3}
      # vertical selection, single line - top one
      do_test_case SELECTIONS_TEST, "Vd", %{
        X
      X line 2
        line 3}
      # vertical selection, lines one and two
      do_test_case SELECTIONS_TEST, "Vjd", %{
        X
      X line 3}
      # vertical selection, last line
      do_test_case SELECTIONS_TEST, "GVd", %{
        X
        line 1
      X line 2}
      # vertical selection, 3 lines, including top one
      do_test_case SELECTIONS_TEST, "Vjjd", %{
        X
      X}
      # character selection, end to start of current line
      do_test_case SELECTIONS_TEST, "v$d", %{
        X
      X line 2
        line 3}
      # character selection, middle of line
      do_test_case SELECTIONS_TEST, "2lvld", %{
          X
      X li 1
        line 2
        line 3}
      # character selection, middle to end
      do_test_case SELECTIONS_TEST, "2lv3ld", %{
         X
      X li
        line 2
        line 3}
      # rectangle selection, a block of 4x3 - fucked completely, its not possible to select the last character of the bottom line!!!
      do_test_case SELECTIONS_TEST, "ll\C-vjjllld", %{
         X 
      X li
        li
        li}
      # rectangle selection, entire document - note, with rect selection vim doesn't cut out end of lines unlike with char selection
      do_test_case SELECTIONS_TEST, "\C-vG$d", %{
        X 
      X 
   
        }
      # rectangle selection, a block of 2x3
      do_test_case SELECTIONS_TEST, "ll\C-vjjld", %{
          X
      X li 1
        li 2
        li 3}
      # character selection, entire document
      do_test_case SELECTIONS_TEST, "vG$d", %{
        X 
      X }
      # character selection, join of first few letters of first line with last few of last line
      do_test_case SELECTIONS_TEST, "2lv2jd", %{
          X 
      X lie 3}
      # character selection, begin of line till end of next line - test with $
      do_test_case SELECTIONS_TEST, "vj$d", %{
        X
      X line 3}
      # character selection, begin of line till end of next line - test with last char - not $
      do_test_case SELECTIONS_TEST, "vj$hld", %{
        X
      X 
        line 3}
   end

   # TODO this is freakkking huugeee

   def test_end_char_mode
      do_test_case %{
        X
      X 12
        12345
        1234}, "j4l", %{  # move to end of second line with the keys - end_char_mode == false
            X
        12
      X 12345
        1234}, "k", %{    # test out non-virtual position by moving up one line, cursor position should move to end of line above therefore
         X
      X 12
        12345
        1234}, "jj", %{   # testing that when not in end_char_mode the cursor actually keeps to the same minimised x position
         X
        12
        12345
      X 1234}, "$kk", %{  # switch to end_char_mode and move down a few lines to check that $ is kept
         X
      X 12
        12345
        1234}, "jj", %{
           X
        12
        12345
      X 1234}, "k", %{    # test that x is not being minimised and is instead keeping to the end
            X
        12
      X 12345
        1234}
      # ugh, this uses internals
      buf = reset_create_and_switch_to
      send_cmd "0"
      buf.lines = [ BufferLine.new("blah"), BufferLine.new("blub") ]
      @app.flush_finish_redraw buf
      assert_equal false, @app.end_char_mode
      assert_equal [0, 0], [@app.curs_x, @app.curs_y]
      send_cmd "$"
      @app.flush_finish_redraw buf
      assert_equal true,  @app.end_char_mode
      assert_equal [3, 0], [@app.curs_x, @app.curs_y]
      assert_equal [3, 0], [buf.x, buf.y]
      send_cmd "j"
      assert_equal true,  @app.end_char_mode
      assert_equal [3, 0], [@app.curs_x, @app.curs_y]
      send_cmd "k"
      assert_equal true,  @app.end_char_mode
      send_cmd "h"
      @app.flush_finish_redraw buf
      assert_equal false,  @app.end_char_mode
      assert_equal [2, 0], [@app.curs_x, @app.curs_y]
      assert_equal [2, 0], [buf.x, buf.y]
      send_cmd "l"
      @app.flush_finish_redraw buf
      assert_equal false, @app.end_char_mode
      assert_equal [3, 0], [buf.x, buf.y]
      assert_equal [3, 0], [@app.curs_x, @app.curs_y]
      do_test_case %{
                X
      X test line
        test line two}, "Aabc", %{
                   X
      X test lineabc
        test line two}, "\C-x\C-hh", %{
                   X
      X test lineabc
        test line two}, "\C-x\C-h-", %{
                    X
      X test lineab-c
        test line two}, "\C-x\C-hlX", %{
                     X
      X test lineab-cX
        test line two}
      buf = reset_create_and_switch_to
      send_cmd "i\C-x\C-h0"
      buf.lines = [ BufferLine.new("blah"), BufferLine.new("blub") ]
      @app.flush_finish_redraw buf
      assert_equal false, @app.end_char_mode
      assert_equal [0, 0], [@app.curs_x, @app.curs_y]
      send_cmd "\C-x\C-h$"
      @app.flush_finish_redraw buf
      assert_equal true,  @app.end_char_mode
      assert_equal [4, 0], [@app.curs_x, @app.curs_y]
      assert_equal [3, 0], [buf.x, buf.y]
      send_cmd "\C-x\C-hk"
      assert_equal true,  @app.end_char_mode
      assert_equal [3, 1], [buf.x, buf.y]
      @app.flush_finish_redraw buf
      assert_equal [4, 1], [@app.curs_x, @app.curs_y]
      send_cmd "\C-x\C-hk"
      assert_equal true,  @app.end_char_mode
      send_cmd "\C-x\C-hh"
      @app.flush_finish_redraw buf
      assert_equal false,  @app.end_char_mode
      assert_equal [3, 0], [@app.curs_x, @app.curs_y]
      assert_equal [3, 0], [buf.x, buf.y]
      send_cmd "\C-x\C-hl"
      @app.flush_finish_redraw buf
      assert_equal true, @app.end_char_mode
      assert_equal [3, 0], [buf.x, buf.y]
      assert_equal [4, 0], [@app.curs_x, @app.curs_y]
      send_cmd "\C-x\C-hl"
      @app.flush_finish_redraw buf
      assert_equal false, @app.end_char_mode
      assert_equal [0, 1], [buf.x, buf.y]
      assert_equal [0, 1], [@app.curs_x, @app.curs_y]
   end

   def test_batsman
      $myedteststub.do_rendering {
         reset_create_and_switch_to
         @app.add_command_binding("\C-k") {
            sbs = @app.widgets.find_all { |sb| sb.is_a? StatusBar }
            sb = sbs.detect { |sb| sb.buffer == @app.current_buffer }
            idx = sbs.index sb
            idx = (idx + 1 ) % sbs.length
            @app.switch_to_buffer sbs[idx].buffer
         }
         @app.add_command_binding("\C-j") {
            sbs = @app.widgets.find_all { |sb| sb.is_a? StatusBar }
            sb = sbs.detect { |sb| sb.buffer == @app.current_buffer }
            idx = sbs.index sb
            idx = (idx - 1 ) % sbs.length
            @app.switch_to_buffer sbs[idx].buffer
         }
         send_cmd "ibuffer 1 text\e:new\ribuffer 2 text\e:new\ribuffer 3 text\e:b1\r"
         check_rendering @app.current_buffer, "batsman1"
         send_cmd "\C-k"
         check_rendering @app.current_buffer, "batsman2"
         send_cmd "\C-k"
         check_rendering @app.current_buffer, "batsman3"
         send_cmd "\C-j\C-j\C-j"
         check_rendering @app.current_buffer, "batsman4"
         send_cmd "\C-j"
         check_rendering @app.current_buffer, "batsman5"
      }
   end

=begin
   def test_selection_rendering
      $myedteststub.do_rendering {
         buf = reset_create_and_switch_to
         tmp_buffer = (0..250).collect {
            |linenum| 
            BufferLine.new "#{" " * (linenum % 10)}: #{linenum}: #{(linenum..linenum+(linenum / 4)).to_a.join " "}"
         }
         buf.lines = tmp_buffer
         check_rendering buf, "selection_rendering1"
         send_cmd "VLjjjjjjjjjjjjjjjjjjjjjjjjjkkkkkkkkkkkk"
         check_rendering buf, "selection_rendering2"
      }
   end
=end

   def test_highlight_cpp
      $myedteststub.do_rendering {
         buf = reset_create_and_switch_to
         do_highlight_case buf, ".cpp", "cpp_1", <<CODE
   /* comment with stuff blah blah blah blah "wheeeeeeeee"
    * blah blah blah
    */
   void main(int *p_blah) {
      int b = 8; // comment why?
      char *blah = "wizzle!!";
      if (b == 8) {
         t = 5;
      }
   }
CODE
         do_highlight_case buf, ".cpp", "cpp_2", <<CODE
   void main(int *p_blah) {
      int b = 8; 
      if (b == 8) {
         t = 5;
      }
   }
CODE
      }
   end

   def test_highlighting_during_edits
      $myedteststub.do_rendering {
         buf = reset_create_and_switch_to
         do_highlight_case buf, ".txt", "plain_text", "blah blah blah\nblah blah blah\nblah blah blah\nblah blah blah"
         buf.lines_highlighted = []
         send_cmd "ib"
         @app.flush_finish_redraw buf
         assert_equal [0], buf.lines_highlighted
         buf.lines_highlighted = []
         send_cmd "bhliju"
         @app.flush_finish_redraw buf
         assert_equal [0], buf.lines_highlighted
      }
   end
   
   def test_highlight_more
      $myedteststub.do_rendering {
         buf = reset_create_and_switch_to
         do_highlight_case buf, ".rb", "more", <<CODE
   my_proc = proc {
      |param1, param2|
      p self
      blah.each do
        |blah|
        p blah
      end
      while true do
        |param4, (a,b)|
        puts blah
      end
      puts(
        THIS_IS_A_CONSTANT ? 0 : 1, # maybe we'd like to highlight the (a ? b : c) construct well? 
        "this is a string!"
      )
      p $oh_look_a_global
      a,b,c = *c # maybe we want to render this? vim doesn't...
      sym = :symbol
      yield 10
   }
CODE
      }
   end

   def test_highlight
      $myedteststub.do_rendering {
         buf = reset_create_and_switch_to
=begin
  # keyword after '=' => not a modifier
  blah = if true
      blah
    else
      blah2
  end
  # ( opens up a state
  blah(if true
        blah
       else
        blah2
       end, 8)
  # todo - any cases other than the two above?
=end
         # TODO - aelexer doesn't grok 'p /blah/'... this is just strange... it must presume its division or something?
         do_highlight_case buf, ".rb", "regexps", <<CODE
"blah" =~ /this is a regexp/
"blah" =~ /this is a multi
   line regexp and we love that/m
"blah" =~ /this is a regexp with some strange things in #\{blah} \\n \\t \\r \\\\/
CODE
         do_highlight_case buf, ".rb", "comments", <<CODE
# this is a comment
print "this isn't a comment..."
=begin
this is also a comment
=end
print "this isn't a comment..."
CODE
         do_highlight_case buf, ".rb", "backslash_continuator", <<CODE
def blah
   blah() \\
      if true
end
CODE
         do_highlight_case buf, ".rb", "question_mark", <<CODE
puts [?a, ?b, ?c]
break if (span1.nil? and span2.nil?) or (span1.nil?)
CODE
         do_highlight_case buf, ".rb", "multi_line_with_specials", <<CODE 
class MyClass
   blah = %{
      \\tblah
      \\t\\tblah
      \\tblah
   }, %{
      blah \\t -> blah?
   }, %q(
      a
      b
      c
   )
   puts %w<a b c>
   puts %q|a b c|
end
CODE
         # interesting bug found by neoneye
         do_highlight_case buf, ".rb", "tabs", <<CODE 
class TestLexerText < Test::Unit::TestCase
	include LexerText
	def format(text)
		lexer = Lexer.new
		lexer.set_states([])  # there are no states in plaintext files
		lexer.set_result([])
		lexer.lex_line(text)
		lexer.result
	end
	def test_format_normal1
		expected = [
			['hell', :text],
			["\\t\\t", :tab],
			["o world\\n   ", :text]
		]
		assert_equal(expected, format("hell\\t\\to world\\n   "))
	end
end
CODE
         send_cmd "jjj"; @app.flush_finish_redraw buf; check_rendering buf, "tabs_cursor_on_tab"
         send_cmd "kkk"; @app.flush_finish_redraw buf
         do_highlight_case buf, ".rb", "multi_line_word", <<CODE 
class MyClass
   blah = %w(
      blah
      blah
   )
end
CODE
         do_highlight_case buf, ".rb", "multi_line", <<CODE 
class MyClass
   blah = %{
      blah
      blah
   }
end
CODE
         do_highlight_case buf, ".rb", "simple1", <<CODE 
class MyClass
end
CODE
         do_highlight_case buf, ".rb", "simple2", <<CODE
module NowWithAModule
   class MyClass
   end
end
CODE
         do_highlight_case buf, ".rb", "function_def", <<CODE
def limit_to_positive num
    return 0 if num < 0
    num
end
CODE
         do_highlight_case buf, ".rb", "unless_block", <<CODE
def limit_to_positive num
    unless true
       fail "everything"
    end
end
CODE
         do_highlight_case buf, ".rb", "until_modifier", <<CODE
    def move_to buffer, x, y
        buffer.x = x
        if y < buffer.top
            scroll_up(buffer)   until line_displayed?(buffer, y)
        elsif y >= (buffer.top + screen_height)
            scroll_down(buffer) until line_displayed?(buffer, y)
        end
        buffer.y = y
    end
CODE
         do_highlight_case buf, ".rb", "heredoc", <<CODE
    my_string = <<EOF
      this is a huge string
EOF
CODE
         do_highlight_case buf, ".rb", "interpolation", 'my_string = "this is a number: #{5 + 6} and it should be eleven!"'
      }
   end

   def test_aelexer_state_machine
      $myedteststub.do_rendering {
         buf = reset_create_and_switch_to
         buf.fname = "mytest.rb"
         code = 't = <<EOF
this is a long string
thingy yeah dude yay
EOF
h = 5'
         buf.lines = code.split("\n").collect { |line| BufferLine.new line }
         EditorApp.invalidate_buffer_line buf, 0 # begins the eof
         @app.redraw buf
         @app.flush_finish_redraw buf
         EditorApp.invalidate_buffer_line buf, 0 # begins the eof
         EditorApp.invalidate_buffer_line buf, 4 # simple non heredoc line
         @app.flush_finish_redraw buf
         assert InternalRendering.verify_rendering("aelexer_state_machine")
      }
   end

   def test_delete
      do_test_case %{
        X 
      X this is a test
        this is another line thingy}, "lldG", %{
        X
      X}
      do_test_case %{
        X
      X this is a test}, "d4l", %{
        X
      X  is a test}
      do_test_case %{
        X
      X line one
        line two
        line three
        line four}, "d2j", %{
        X
      X line four}
      do_test_case %{
        X
      X line one
        line two
        line three
        line four}, "gg0dGipibble", %{
             X
      X pibble}
   end

   def test_auto_finish_pair
      do_test_case TextWithCursor.new(%{
        X
      X }, ".rb"), ":set autopair=true\rimy_block = proc {", %{
                         X
      X my_block = proc {}}, " ", %{
                          X
      X my_block = proc {  }}
      do_test_case TextWithCursor.new(%{
        X
      X }, ".rb"), ":set autopair=true\rimy_block = proc {", %{
                         X
      X my_block = proc {}}, "\r", %{
           X
        my_block = proc {
      X     
        }}
   end

   def test_autoindent
      buf = reset_create_and_switch_to
      buf.fname = "autoindent.rb" 
      after = TextWithCursor.new %{
        X
      X def blah
            print 5
        end
        blah.each {
            waza
        }
        blah.each do
            blah
        end
        class << self; self end.send(:define_method, :foo) { }
        a = b + c(bibble,
                  babble)
        }
=begin
        5.times do |blah|
           blah
        end
=end
      send_cmd "idef blah\rprint 5\rend\rblah.each {\rwaza\r}\rblah.each do\rblah\rend\rclass << self; self end.send(:define_method, :foo) { }\ra = b + c(bibble,\rbabble)\r"
      assert_equal after.text, buf.text
      # going overboard with ?o testing.. but why not :P
      send_cmd "\egg0dGidef blah\rend\rblah.each {\r}\rblah.each do\rend\rclass << self; self end.send(:define_method, :foo) { }\ra = b + c(bibble,\rbabble)\r"
      send_cmd "\eggoprint 5\ejjjOwaza\ejjjOblah\e"
      assert_equal after.text, buf.text
      send_cmd "\eggVG<<<<"
      assert_equal after.text.gsub(/^\s*(.*)$/,'\\1'), buf.text
      send_cmd "\eggVG="
      assert_equal after.text, buf.text
   end

   def test_hardtabs
      buf = reset_create_and_switch_to
      before = TextWithCursor.new %{
        X
      X if blah
        \tacdsa
        \tblah {
        \t\tblub
        \r}
        blub}
      buf.x, buf.y = before.x, before.y
      buf.lines = before.buffer_lines
      send_cmd "j"
      @app.flush_finish_redraw buf
      assert_equal [0, 1], [@app.curs_x, @app.curs_y]
      send_cmd "l"
      @app.flush_finish_redraw buf
      assert_equal [8, 1], [@app.curs_x, @app.curs_y]
   end

   def test_cursor
      $myedteststub.do_rendering {
      buf = reset_create_and_switch_to
      before = TextWithCursor.new %{
        X
      X line 1
        line 2
        line 3
        
        above is an empty line}
      buf.x, buf.y = before.x, before.y
      buf.lines = before.buffer_lines
      send_cmd "l"; @app.flush_finish_redraw buf; assert_equal [1, 0], [@app.curs_x, @app.curs_y]
      send_cmd "l"; @app.flush_finish_redraw buf; assert_equal [2, 0], [@app.curs_x, @app.curs_y]
      check_rendering @app.current_buffer, "cursor_render_normal"
      send_cmd "jjj"
      check_rendering @app.current_buffer, "cursor_render_blank_line"
      send_cmd "i"
      check_rendering @app.current_buffer, "cursor_render_insert_mode_blank_line"
      send_cmd "\ek"
      check_rendering @app.current_buffer, "cursor_render_insert_mode_normal"
      send_cmd "A"
      check_rendering @app.current_buffer, "cursor_render_line_append"
      send_cmd "\e"
      check_rendering @app.current_buffer, "cursor_render_line_normal_after_append"
      send_cmd "k"
      check_rendering @app.current_buffer, "cursor_render_line_movement_after_normal_after_append"
      }
   end

   def test_textwidth
      do_test_case %{
        X 
      X}, ":set tw=10\riwhat is the point in this if it doesn't even work exactly?", %{
               X
        what is
        the point
        in this
        if it
        doesn't
        even work
      X exactly?}
   end

   def test_letter_finds
      buf = reset_create_and_switch_to
      before = TextWithCursor.new %{
        X
      X abcdef12345}
      buf.x, buf.y = before.x, before.y
      buf.lines = before.buffer_lines
      send_cmd "fc"; assert_equal  [2, 0], [buf.x, buf.y]
      send_cmd "f5"; assert_equal [10, 0], [buf.x, buf.y]
      send_cmd "Tf"; assert_equal  [6, 0], [buf.x, buf.y]
      send_cmd "Fa"; assert_equal  [0, 0], [buf.x, buf.y]
      send_cmd "tc"; assert_equal  [1, 0], [buf.x, buf.y]
      send_cmd "t5"; assert_equal  [9, 0], [buf.x, buf.y]
      do_test_case %{
             X
      X blub(abu, bji, coc)}, "ct,blah\e", %{
                 X
      X blub(blah, bji, coc)}
      do_test_case %{
             X
      X example_string = "blb ucdsajdewi" + 5}, "f\"df\"", %{
                         X
      X example_string =  + 5}
   end

   def test_undo_redo_read_only_file_edit
      do_kill_difflogs

      fname = "/etc/hostname"

      reset_create_and_switch_to
      buf = startup_and_load fname
      send_cmd "iline one\rline two\rline three\r\eiline four\e"
      send_cmd "ggVGd"
      buf = restart_with_difflog fname
      do_kill_difflogs
   end

   def test_undo_redo_5
      do_kill_difflogs

      fname = "/tmp/blahhucdsa"

      begin
         $myedteststub.do_rendering {
            reset_create_and_switch_to
            buf = startup_and_load fname
            send_cmd "iline one\rline two\rline three\r\eiline four\e"
            send_cmd "ggVGd"
            buf = restart_with_difflog fname
            check_rendering @app.current_buffer, "undo_redo_5"
         }
      ensure
         File.delete(fname) if File.exists? fname
         do_kill_difflogs
      end
   end

   def test_undo_redo
      do_kill_difflogs

      fname = "/tmp/blahhucdsa"

      # send_cmd "Onewer yet first line\euggdG"  - fix me

      begin
         buf = startup_and_load fname               # NOTICE THE \e
         send_cmd "iline one\rline two\rline three\r\eiline four"
         should_be = buf.text
         buf = restart_with_difflog fname
         assert_equal should_be, buf.text
         send_cmd "\einew first line\r\e:q\r"
         assert_equal "file unsaved!", @app.status_bar.text
         assert !$was_closed
         should_be = buf.text
         send_cmd ":w\r:q\r"
         assert $was_closed
         buf = restart_with_difflog fname
         assert_equal should_be, buf.text
         send_cmd "ianother first line\r"
         file_should_be = should_be
         should_be      = buf.text
         send_cmd "\e:qk\r"
         assert $was_closed
         assert_equal file_should_be + "\n", IO.read(fname)
         buf = restart_with_difflog fname
         assert_equal should_be, buf.text
         # repeat above again
         send_cmd ":qk\r"
         assert $was_closed
         assert_equal file_should_be + "\n", IO.read(fname)
         buf = restart_with_difflog fname
         assert_equal should_be, buf.text
         # test that :wq now saves
         send_cmd ":wq\r"
         assert $was_closed
         assert_equal should_be + "\n", IO.read(fname)
         buf = restart_with_difflog fname
         assert_equal should_be, buf.text
         # test that :q! reverts any modifications on reload
         send_cmd "Onewer yet first line\eIassing about a bit\eu"
         file_should_be = should_be
         should_be      = buf.text
         send_cmd ":q!\r"
         assert $was_closed
         assert_equal file_should_be + "\n", IO.read(fname)
         buf = restart_with_difflog fname
         assert_equal file_should_be, buf.text
         send_cmd "\C-r"
         assert_equal should_be, buf.text
         send_cmd "u"
         assert_equal file_should_be, buf.text
         send_cmd "Onewer yet first line\eIassing about a bit\euicdsacdsacdsacdsa\e"
         should_be      = buf.text
         send_cmd ":q!\r"
         assert $was_closed
         buf = restart_with_difflog fname
         assert_equal file_should_be, buf.text
         send_cmd "\C-r\C-r\C-r\C-r\C-r"
         assert_equal should_be, buf.text
      ensure
         File.delete(fname) if File.exists? fname
         do_kill_difflogs
      end
   end

   def branch_id buf, _id
      id = buf.dlog.branch_id _id
      buf.dlog.instance_eval { @ids2changesets[id] = [] }
      id
   end

   def inc_id buf, _id
      id = buf.dlog.inc_id _id
      buf.dlog.instance_eval { @ids2changesets[id] = [] }
      id
   end

   def test_branch_id
      buf = reset_create_and_switch_to
      assert_equal "#1.1",          branch_id(buf, nil)
      assert_equal "#1.1#1.1",      branch_id(buf, "#1.1")
      assert_equal "#1.1#1.1#1.1",  branch_id(buf, "#1.1#1.1")
      assert_equal "#2.1",          branch_id(buf, nil)
      assert_equal "#2.1#1.2",      inc_id(buf, "#2.1#1.1")
      assert_equal "#2.1#1.3",      inc_id(buf, "#2.1#1.2")
      assert_equal "#2.1#2.3",      inc_id(buf, "#2.1#2.2")
      assert_equal "#1.1#3.1#1.1",  branch_id(buf, "#1.1#3.1")
      assert_equal "#1.1#1.1#2.1",  buf.dlog.prev_id("#1.1#1.1#2.2")
      assert_equal "#1.1#1.1",      buf.dlog.prev_id("#1.1#1.1#2.1")
      assert_equal "#1.1#1.1#2.1",  buf.dlog.prev_id("#1.1#1.1#2.2")
      assert_equal "#1.1#1.1",      buf.dlog.prev_id("#1.1#1.1#2.1")
      assert_equal "#1.1",          buf.dlog.prev_id("#1.1#1.1")
      assert_equal "#2.1",          buf.dlog.prev_id("#2.2")
      assert_equal nil,             buf.dlog.prev_id("#2.1")
      assert_equal nil,             buf.dlog.prev_id("#1.1")
   end

   def test_undo_redo_2
      do_kill_difflogs

      fname = "/tmp/blahhucdsa"

      begin
         buf = startup_and_load fname
         send_cmd "iblah blah blah"
         send_cmd "\eu"
         send_cmd "iblub blub blub"
         send_cmd "\r\e" # NOTICE THE \e
         should_be = buf.text
         buf = restart_with_difflog fname
         assert_equal should_be, buf.text
         send_cmd "u"
         assert_equal "", buf.text
         send_cmd "\C-r"
         assert_equal should_be, buf.text
         send_cmd "uuuuu"
      ensure
         File.delete(fname) if File.exists? fname
         do_kill_difflogs
      end
   end

   def test_undo_redo_8
      do_kill_difflogs

      fname = "/tmp/blahhucdsa"

      begin
         buf = startup_and_load fname
         send_cmd "ifirst line\eosecond line\e"
         should_be = buf.text
         send_cmd ":wq\r"
         assert $was_closed
         buf = restart_with_difflog fname
         send_cmd "uu"
         send_cmd ":qk\r"
         assert $was_closed
         buf = restart_with_difflog fname
         send_cmd "\C-r" * 5
         assert_equal should_be, buf.text
         send_cmd ":qk\r"
         buf = restart_with_difflog fname
      ensure
         File.delete(fname) if File.exists? fname
         do_kill_difflogs
      end
   end

   def test_undo_redo_7
      do_kill_difflogs

      fname = "/tmp/blahhucdsa"

      begin
         buf = startup_and_load fname
         send_cmd "ifirst line\eosecond line\e"
         should_be = buf.text
         send_cmd ":wq\r"
         assert $was_closed
         buf = restart_with_difflog fname
         send_cmd "uu"
         send_cmd ":qk\r"
         assert $was_closed
         buf = restart_with_difflog fname
         send_cmd "\C-r" * 5
         assert_equal should_be, buf.text
      ensure
         File.delete(fname) if File.exists? fname
         do_kill_difflogs
      end
   end

   def test_undo_redo_6
      do_kill_difflogs

      fname = "/tmp/blahhucdsa"

      begin
         buf = startup_and_load fname
         send_cmd "ifirst line\eisecond line\e"
         send_cmd ":wq\r"
         assert $was_closed
         buf = startup_and_load fname
         send_cmd "uu\C-r"
         send_cmd ":q\r"
         assert !$was_closed
      ensure
         File.delete(fname) if File.exists? fname
         do_kill_difflogs
      end
   end

   def test_undo_redo_3
      do_kill_difflogs

      fname = "/tmp/blahhucdsa"

      begin
         buf = startup_and_load fname
         send_cmd "iline one\eoline two\eoline three"
         should_be = buf.text
         buf = restart_with_difflog fname
         assert_equal should_be, buf.text
         send_cmd "u"
         assert_equal "line one\nline two", buf.text
         send_cmd "\C-r"
         assert_equal should_be, buf.text
         send_cmd "uuuuu"
      ensure
         File.delete(fname) if File.exists? fname
         do_kill_difflogs
      end
   end

   def test_undo_redo_4
      do_kill_difflogs

      fname = "/tmp/blahhucdsa"

      begin
         buf = startup_and_load fname
         send_cmd "iline one\eVd"
         should_be = buf.text
         buf = restart_with_difflog fname
         assert_equal should_be, buf.text
         send_cmd "\C-r"
      ensure
         File.delete(fname) if File.exists? fname
         do_kill_difflogs
      end
   end

   def test_x_at_eol
      do_test_case %{
        X 
      X fun "arg"
        blub "bugs"}, "$x", %{
               X
      X fun "arg
        blub "bugs"}
   end

   def test_macro
      do_test_case %{
        X 
      X fun "arg"
        blub "bugs"}, "qx0$xBr:q", %{
            X
      X fun :arg
        blub "bugs"}, "j@x", %{
             X
        fun :arg
      X blub :bugs}
   end

   def test_search
      buf = reset_create_and_switch_to
      before = TextWithCursor.new %{
        X
      X one one two two three three
        three four five six seven eight
        blah blah blah blah blah five blah
        blah blah blah blah four blah
        blah three blah blah five blah
        two blah 
        blah blah blah one blah five blah}
      buf.x, buf.y = before.x, before.y
      buf.lines = before.buffer_lines
      send_cmd "/"
      assert_equal "enter search term: ", @app.status_bar.text
      send_cmd "o"
      assert_equal ":) - o", @app.status_bar.text
      assert_equal [0, 0], [buf.x, buf.y]
      send_cmd "ne"
      assert_equal ":) - one", @app.status_bar.text
      assert_equal [0, 0], [buf.x, buf.y]
      send_cmd " two"
      assert_equal ":) - one two", @app.status_bar.text
      assert_equal [0, 0], [buf.x, buf.y]
      send_cmd "\b\b\b\b"
      assert_equal ":) - one", @app.status_bar.text
      assert_equal [0, 0], [buf.x, buf.y]
      send_cmd "\e/seven\r"
      assert_equal ":) - seven", @app.status_bar.text
      assert_equal [20, 1], [buf.x, buf.y]
      send_cmd "/three\r"
      assert_equal ":) - three", @app.status_bar.text
      assert_equal [5, 4], [buf.x, buf.y]
      send_cmd "/three\r"
      assert_equal ":) - three", @app.status_bar.text
      assert_equal [5, 4], [buf.x, buf.y]
      send_cmd "/two\r"
      assert_equal ":) - two", @app.status_bar.text
      assert_equal [0, 5], [buf.x, buf.y]
      send_cmd "/\r"
      assert_equal ":) - two", @app.status_bar.text
      assert_equal [8, 0], [buf.x, buf.y]
      send_cmd "/\r"
      assert_equal ":) - two", @app.status_bar.text
      assert_equal [12, 0], [buf.x, buf.y]
      send_cmd "/blah\r" 
      assert_equal [0, 2], [buf.x, buf.y]
      send_cmd "n"; assert_equal [5,  2], [buf.x, buf.y]
      send_cmd "n"; assert_equal [10, 2], [buf.x, buf.y]
      send_cmd "n"; assert_equal [15, 2], [buf.x, buf.y]
      send_cmd "n"; assert_equal [20, 2], [buf.x, buf.y]
      send_cmd "n"; assert_equal [30, 2], [buf.x, buf.y]
      send_cmd "n"; assert_equal [0,  3], [buf.x, buf.y]
      send_cmd "n"; assert_equal [5,  3], [buf.x, buf.y]
      send_cmd "n"; assert_equal [10, 3], [buf.x, buf.y]
      send_cmd "n"; assert_equal [15, 3], [buf.x, buf.y]
      blah = TextWithCursor.new %{
         X
      X #!/usr/bin/ruby
        require 'rbconfig'
        $win32 = ::Config::CONFIG["arch"] =~ /dos|win32/i
        $:.unshift File.dirname((File.readlink($0) rescue $0)) unless $win32 
        require "curses-ui"
        require "shikaku"}
      buf.x, buf.y = blah.x, blah.y
      buf.lines = blah.buffer_lines
      send_cmd "/res\r"
      assert_equal [43,  3], [buf.x, buf.y]
      send_cmd "/shi\r"
      assert_equal [9,  5], [buf.x, buf.y]
      send_cmd "/blubbble\r"
      assert_equal [9,  5], [buf.x, buf.y]
      send_cmd "n"
      assert_equal [9,  5], [buf.x, buf.y]
   end

   def test_completion
      buf = reset_create_and_switch_to
      require 'tempfile'
      tf = Tempfile.new "completion_init_script"
      tf.puts %{
         Ruvi::Completion::WordCompleter.new self
      }
      tf.flush
      @app.load_script_file tf.path
      text = TextWithCursor.new %{
         X
       X $blah,bugga
         completion $blah
      }
      buf.lines = text.buffer_lines
      buf.x, buf.y = text.x, text.y
      send_cmd "ocomp\C-n"
      after = TextWithCursor.new %{
         X
       X $blah,bugga
         completion
         completion $blah
      }
      assert_equal after.text, buf.text
      send_cmd "\rblah\C-n"
      after = TextWithCursor.new %{
         X
       X $blah,bugga
         completion
         blah
         completion $blah
      }
      assert_equal after.text, buf.text
      assert_equal "Sorry, no completion found!", @app.status_bar.text
      send_cmd "\rwibble\rwib\C-n"
      after = TextWithCursor.new %{
         X
       X $blah,bugga
         completion
         blah
         wibble
         wibble
         completion $blah
      }
      assert_equal after.text, buf.text
   end

   def test_filename_completion
      buf = reset_create_and_switch_to
      require 'tempfile'
      tf = Tempfile.new "filename_completion_init_script"
      tf.puts %{
         Ruvi::Completion::FilenameCompleter.new self
      }
      tf.flush
      @app.load_script_file tf.path
      text = TextWithCursor.new %{
                 X
       X /home/al}
      buf.lines = text.buffer_lines
      buf.x, buf.y = text.x, text.y
      send_cmd "\C-x\C-f"
      after = TextWithCursor.new %{
                   X
       X /home/alex}
      assert_equal after.text, buf.text
   end

   def test_rrb
      buf = reset_create_and_switch_to
      require 'tempfile'
      tf = Tempfile.new "rrb_init_script"
      tf.puts %{
         Ruvi::RRBPlugin.new self
      }
      tf.flush
      begin
      @app.load_script_file tf.path
      rescue NameError => e
         return
      end
      before = TextWithCursor.new %{
             X
        $global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method n
            puts $global_var + n
          end
          def blah
            my_method 2
            @@class_var = 20
            @instance_var = 10
      X     local_var = 10
            puts local_var
            puts @instance_var
            puts @@class_var
            puts $global_var
            puts Blah::MY_CONSTANT, MY_CONSTANT, Waza::MY_CONSTANT
          end
        end
        class BlahSub < Blah

        end}
      buf.lines = before.buffer_lines
      buf.x, buf.y = before.x, before.y
      buf.fname = "/tmp/mytestfile"
      after = TextWithCursor.new %{
             X
        $global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method n
            puts $global_var + n
          end
          def blah
            my_method 2
            @@class_var = 20
      X     @instance_var = 10
            new_name_of_local = 10
            puts new_name_of_local
            puts @instance_var
            puts @@class_var
            puts $global_var
            puts Blah::MY_CONSTANT, MY_CONSTANT, Waza::MY_CONSTANT
          end
        end
        class BlahSub < Blah

        end}
      send_cmd ":w\r"
      $user_input << "new_name_of_local"
      send_cmd ":rrb_rename_local_vars\r"
      assert_equal after.text, buf.text
      buf.x, buf.y = after.x, after.y
      $user_input << "@new_name_of_instance_var"
      send_cmd ":rrb_rename_instance_var\r"
      after = TextWithCursor.new %{
              X
        $global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method n
            puts $global_var + n
          end
          def blah
            my_method 2
      X     @@class_var = 20
            @new_name_of_instance_var = 10
            new_name_of_local = 10
            puts new_name_of_local
            puts @new_name_of_instance_var
            puts @@class_var
            puts $global_var
            puts Blah::MY_CONSTANT, MY_CONSTANT, Waza::MY_CONSTANT
          end
        end
        class BlahSub < Blah

        end}
      assert_equal after.text, buf.text
      buf.x, buf.y = after.x, after.y
      $user_input << "@@new_name_of_class_var"
      send_cmd ":rrb_rename_class_var\r"
      after = TextWithCursor.new %{
              X
      X $global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method n
            puts $global_var + n
          end
          def blah
            my_method 2
            @@new_name_of_class_var = 20
            @new_name_of_instance_var = 10
            new_name_of_local = 10
            puts new_name_of_local
            puts @new_name_of_instance_var
            puts @@new_name_of_class_var
            puts $global_var
            puts Blah::MY_CONSTANT, MY_CONSTANT, Waza::MY_CONSTANT
          end
        end
        class BlahSub < Blah

        end}
      assert_equal after.text, buf.text
      buf.x, buf.y = after.x, after.y
      $user_input << "$new_name_of_global_var"
      send_cmd ":rrb_rename_global_var\r"
      after = TextWithCursor.new %{
                X
        $new_name_of_global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          MY_CONSTANT = 5
          attr_accessor :instance_var
      X   def my_method n
            puts $new_name_of_global_var + n
          end
          def blah
            my_method 2
            @@new_name_of_class_var = 20
            @new_name_of_instance_var = 10
            new_name_of_local = 10
            puts new_name_of_local
            puts @new_name_of_instance_var
            puts @@new_name_of_class_var
            puts $new_name_of_global_var
            puts Blah::MY_CONSTANT, MY_CONSTANT, Waza::MY_CONSTANT
          end
        end
        class BlahSub < Blah

        end}
      assert_equal after.text, buf.text
      buf.x, buf.y = after.x, after.y
      $user_input << "new_my_method"
      send_cmd ":rrb_rename_method\r"
      after = TextWithCursor.new %{
          X
        $new_name_of_global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
      X   MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method(*arg); raise 'Blah#my_method is renamed new_my_method' end
          def new_my_method n
            puts $new_name_of_global_var + n
          end
          def blah
            new_my_method 2
            @@new_name_of_class_var = 20
            @new_name_of_instance_var = 10
            new_name_of_local = 10
            puts new_name_of_local
            puts @new_name_of_instance_var
            puts @@new_name_of_class_var
            puts $new_name_of_global_var
            puts Blah::MY_CONSTANT, MY_CONSTANT, Waza::MY_CONSTANT
          end
        end
        class BlahSub < Blah

        end}
      assert_equal after.text, buf.text
      buf.x, buf.y = after.x, after.y
      $user_input << "NEW_MY_CONSTANT"
      send_cmd ":rrb_rename_constant\r"
      after = TextWithCursor.new %{
             X
        $new_name_of_global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          NEW_MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method(*arg); raise 'Blah#my_method is renamed new_my_method' end
          def new_my_method n
            puts $new_name_of_global_var + n
          end
          def blah
            new_my_method 2
            @@new_name_of_class_var = 20
            @new_name_of_instance_var = 10
            new_name_of_local = 10
      X     puts new_name_of_local
            puts @new_name_of_instance_var
            puts @@new_name_of_class_var
            puts $new_name_of_global_var
            puts Blah::NEW_MY_CONSTANT, NEW_MY_CONSTANT, Waza::MY_CONSTANT
          end
        end
        class BlahSub < Blah

        end}
      assert_equal after.text, buf.text
      buf.x, buf.y = after.x, after.y
      send_cmd "V4j"
      $user_input << "puts_lots"
      send_cmd ":rrb_extract_method\r"
      after = TextWithCursor.new %{
             X
        $new_name_of_global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          NEW_MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method(*arg); raise 'Blah#my_method is renamed new_my_method' end
          def new_my_method n
            puts $new_name_of_global_var + n
          end
          def puts_lots(new_name_of_local)
            puts new_name_of_local
            puts @new_name_of_instance_var
            puts @@new_name_of_class_var
            puts $new_name_of_global_var
            puts Blah::NEW_MY_CONSTANT, NEW_MY_CONSTANT, Waza::MY_CONSTANT
          end
          def blah
            new_my_method 2
            @@new_name_of_class_var = 20
            @new_name_of_instance_var = 10
            new_name_of_local = 10
            puts_lots(new_name_of_local)
          end
        end
        class BlahSub < Blah
      X
        end}
      $user_input << "4" # Blah::blah
      $user_input << "1" # BlahSub
      buf.x, buf.y = after.x, after.y
      send_cmd ":rrb_push_down_method\r"
      after = TextWithCursor.new %{
             X
        $new_name_of_global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          NEW_MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method(*arg); raise 'Blah#my_method is renamed new_my_method' end
          def new_my_method n
            puts $new_name_of_global_var + n
          end
          def puts_lots(new_name_of_local)
            puts new_name_of_local
            puts @new_name_of_instance_var
            puts @@new_name_of_class_var
            puts $new_name_of_global_var
            puts Blah::NEW_MY_CONSTANT, NEW_MY_CONSTANT, Waza::MY_CONSTANT
      X   end
        end
        class BlahSub < Blah
          def blah
            new_my_method 2
            @@new_name_of_class_var = 20
            @new_name_of_instance_var = 10
            new_name_of_local = 10
            puts_lots(new_name_of_local)
          end
        end}
      $user_input << "4" # Blah::blah
      $user_input << "3" # BlahSub
      buf.x, buf.y = after.x, after.y
      send_cmd "o\e"
      send_cmd ":rrb_pull_up_method\r"
      after = TextWithCursor.new %{
             X
        $new_name_of_global_var = 5
        class Waza; MY_CONSTANT = 10; end
        class Blah
          NEW_MY_CONSTANT = 5
          attr_accessor :instance_var
          def my_method(*arg); raise 'Blah#my_method is renamed new_my_method' end
          def new_my_method n
            puts $new_name_of_global_var + n
          end
          def puts_lots(new_name_of_local)
            puts new_name_of_local
            puts @new_name_of_instance_var
            puts @@new_name_of_class_var
            puts $new_name_of_global_var
            puts Blah::NEW_MY_CONSTANT, NEW_MY_CONSTANT, Waza::MY_CONSTANT
          end
      X   def blah
            new_my_method 2
            @@new_name_of_class_var = 20
            @new_name_of_instance_var = 10
            new_name_of_local = 10
            puts_lots(new_name_of_local)
          end
        end
        class BlahSub < Blah
        end}
      assert_equal after.text, buf.text
   end

   def test_paste
      do_test_case %{
        X
      X test one
        test two}, "v$yo\ep", %{
        X
        test one
      X
        test one
        test two}
      do_test_case %{
        X
      X test one
        test two}, "y$o\ep", %{
        X
        test one
      X test one
        test two}
      do_test_case %{
        X
        test one
      X test two
        test three
        test four}, "Vjyp", %{
        X
        test one
        test two
        test three
      X test two
        test three
        test four}
      do_test_case %{
        X
      X test one
        test two
        test three
        test four}, "\"aVyj\"bVyjj\"ap", %{
        X
        test one
        test two
        test three
        test four
      X test one}, "\"bp", %{
        X
        test one
        test two
        test three
        test four
        test one
      X test two}
   end

   def test_change_rest_of_line
      do_test_case %{
        X
      X test line
        test line two}, "wC", %{
            X
      X test 
        test line two}
   end

   def test_change_to_eol
      # merge somewhere else, or add more?
      do_test_case %{
        X
      X test one}, "c$", %{
        X
      X }
   end

   def test_cmd_completion
      reset_create_and_switch_to
      send_cmd ":b"; assert_equal "b", @app.get_cmd_line
      send_cmd "u" ; assert_equal "bu", @app.get_cmd_line
      send_cmd "\b"; assert_equal "b", @app.get_cmd_line
      send_cmd "\b"; assert_equal "", @app.get_cmd_line
      send_cmd "\e:buf\t"
      assert_equal "buffer", @app.get_cmd_line
      assert_equal ":buffer", @app.status_bar.text
      send_cmd "\e:w\t"
      assert_equal ":w (...,r!,set,[w],wa,wq)", @app.status_bar.text
      send_cmd "\t"
      assert_equal ":wa (...,set,w,[wa],wq)", @app.status_bar.text
      send_cmd "\e:edi\t"
      assert_equal ":edit", @app.status_bar.text
      @app.setup_cmd("exampleone", /^exampleone$/) { |a,b| }
      @app.setup_cmd("exampletwo", /^exampletwo$/) { |a,b| }
      send_cmd "\e:exam\t"
      assert_equal ":example (exampleone,exampletwo)", @app.status_bar.text
      send_cmd "\t"
      assert_equal ":exampleone (...,ed,edit,[exampleone],exampletwo,new,...)", @app.status_bar.text
      send_cmd "\t"
      assert_equal ":exampletwo (...,edit,exampleone,[exampletwo],new,q,...)", @app.status_bar.text
      send_cmd "\t"
      assert_equal ":new (...,exampleone,exampletwo,[new],q,q!,...)", @app.status_bar.text
   end
   
   def filename_completion_test &block
      tf = Tempfile.new("ruvi_filename_completion_test")
      dirname = tf.path + ".dir/"
      fail "temp dir already exists!" if File.exists? dirname
      Dir.mkdir dirname
      filenames = %w(a b c d ab abc abcd abcde zxy).collect{|name|dirname+name}
      FileUtils.touch filenames
      begin
         block.call dirname
      ensure
         tf.close!
         FileUtils.rm filenames
         Dir.rmdir dirname
      end
   end
   
   def test_cmd_ed_completion
      filename_completion_test {
         |dirname|
         reset_create_and_switch_to
         send_cmd ":ed #{dirname}\t"
         assert_equal "ed #{dirname}a", @app.get_cmd_line
         assert_equal ":ed #{dirname}a ([a],ab,abc,...)", @app.status_bar.text
         send_cmd "\t"
         assert_equal "ed #{dirname}ab", @app.get_cmd_line
         assert_equal ":ed #{dirname}ab (a,[ab],abc,abcd,...)", @app.status_bar.text
         send_cmd "\t"
         assert_equal "ed #{dirname}abc", @app.get_cmd_line
         assert_equal ":ed #{dirname}abc (a,ab,[abc],abcd,abcde,...)", @app.status_bar.text
         send_cmd "\t"
         assert_equal "ed #{dirname}abcd", @app.get_cmd_line
         assert_equal ":ed #{dirname}abcd (...,ab,abc,[abcd],abcde,b,...)", @app.status_bar.text
     }
   end

   def test_settings
      reset_create_and_switch_to
      send_cmd ":set blah=5\r"
      assert_equal "5", @app.settings[:blah]
   end

   def test_remove_binding
      buf = reset_create_and_switch_to
      b = 0
      binding1 = proc { b = 1 }
      binding2 = proc { b = 2 }
      @app.add_command_binding "\C-b", &binding1
      assert_equal binding1, @app.delete_command_binding("\C-b")
      assert_equal nil, @app.delete_command_binding("\C-b")
   end

   def test_mornfalls_bindings
      buf = reset_create_and_switch_to
      buf.lines.delete_at 0
      5.times { buf.lines << BufferLine.new("1234567890") }
      # @app.add_command_binding("h") { @app.send_key ?h }
      @app.add_command_binding("t") { @app.send_key ?j }
      old_proc = @app.delete_command_binding("n")
      @app.add_command_binding("n") { @app.send_key ?k }
      @app.add_command_binding("s") { @app.send_key ?l }
      @app.add_command_binding("m", &old_proc)
      assert_equal [0,0], [buf.x, buf.y]
      send_cmd "t"; assert_equal [0,1], [buf.x, buf.y]
      send_cmd "n"; assert_equal [0,0], [buf.x, buf.y]
      send_cmd "s"; assert_equal [1,0], [buf.x, buf.y]
      send_cmd "/123\r"; assert_equal [0,1], [buf.x, buf.y]
      send_cmd "m"; assert_equal [0,2], [buf.x, buf.y]
      send_cmd "h"; assert_equal [9,1], [buf.x, buf.y]
   end

   def test_add_command_binding
      # TODO - add testing for conflict detection in keybindings - not yet coded!
      buf = reset_create_and_switch_to
      b = 1
      @app.add_command_binding("\C-b") {
         b = 0
      }
      @app.add_command_binding("\C-p") {
         b = 2
      }
      assert_equal 1, b
      send_cmd "\C-b"
      assert_equal 0, b
      send_cmd "\C-p"
      assert_equal 2, b
      b = 0
      @app.add_command_binding("\C-a1") {
         b = 1
      }
      @app.add_command_binding("\C-a2") {
         b = 2
      }
      assert_equal 0, b
      send_cmd "\C-a1"
      assert_equal 1, b
      send_cmd "\C-a2"
      assert_equal 2, b
      @app.add_command_binding("\C-t") {
         buf = EditorApp.new_buffer @app, :no_blank_line
         @app.switch_to_buffer buf
         `echo this is a test string; echo and this another`.each_line {
            |line| 
            buf.lines << BufferLine.new(line.chomp)
         }
      }
      assert_equal "", buf.text
      send_cmd "\C-t"
      assert_equal "this is a test string\nand this another", buf.text
   end

   def test_save_load_file
      fname = make_tmpfname
      do_test_case %{
        X 
      X}, "ithis is a test!\e:w #{fname}\r^cwWHAT\e", %{
            X
      X WHAT is a test!}
      do_test_case %{
        X 
      X}, ":ed #{fname}\r", %{
        X
      X this is a test!}
      File.delete(fname)
      # File.delete("+#{fname}.edlog") # assert that this doesn't exist...
   end

   public_instance_methods.each {
      |meth| 
      next if meth !~ /^test.*/ or meth.to_sym == DO_TEST
      remove_method meth.to_sym
   } if defined? DO_TEST

end
