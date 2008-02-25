module Ruvi

    class EditorApp

    module BaseFakeBufferModule
        def BaseFakeBufferModule.new_ext_buffer app, extension
            b = EditorApp.new_buffer app, :no_blank_line, :fake_buffer
            b.extend extension
            return b
        end
        def BaseFakeBufferModule.clear_extension_buffers app, extension
            app.clear_buffers_with_extension BaseFakeBufferModule
        end
    end
    
    module BufferListExtension
        attr_accessor :old_buf
        def BufferListExtension.create_buffer app
            clear_extension_buffers app
            b = BaseFakeBufferModule.new_ext_buffer app, BufferListExtension
            b.old_buf = app.current_buffer
            return b
        end
        def BufferListExtension.clear_extension_buffers app
            BaseFakeBufferModule.clear_extension_buffers app, BufferListExtension
        end
    end
    
    module HierarchyListExtension
        attr_accessor :old_buf
        def HierarchyListExtension.create_buffer app
            clear_extension_buffers app
            b = BaseFakeBufferModule.new_ext_buffer app, HierarchyListExtension
            b.old_buf = app.current_buffer
            return b
        end
        def HierarchyListExtension.clear_extension_buffers app
            BaseFakeBufferModule.clear_extension_buffers app, HierarchyListExtension
        end
    end

    end
end

