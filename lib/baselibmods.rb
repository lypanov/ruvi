class Numeric
    def clamp_to bottom, top
        top_clamped = [self, top].min
        return [bottom,top_clamped].max
    end
end
    
class Array
    def insert_after idx, item
        if idx == -1
           self << item
        else
            after = slice! idx..length
            push << item
            concat after unless after.nil?
        end
    end
end

