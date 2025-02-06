module Diff 
  # Implements Myers' diff algorithm to find the shortest edit sequence between two sequences
  class Myers 
        # Convenience method to create and run a diff
        def self.diff(a, b)
          Myers.new(a, b).diff 
        end

        def initialize(a, b)
          @a, @b = a, b
        end

        # Generates a sequence of diff operations (insert, delete, equal)
        # by backtracking through the shortest edit path
        def diff
          diff = []

          backtrack do |prev_x, prev_y, x, y|
            a_line, b_line = @a[prev_x], @b[prev_y]

            if x == prev_x
              diff.push(Edit.new(:ins, nil, b_line))
            elsif y == prev_y
              diff.push(Edit.new(:del, a_line, nil))
            else
              diff.push(Edit.new(:eql, a_line, b_line))
            end
          end
          diff.reverse
        end

        def unused
          
        end
        
        # Walks backwards through the shortest edit path to reconstruct the diff operations
        # For each step, yields the previous and current positions (x,y coordinates)
        # in both sequences
        def backtrack 
          x, y = @a.size, @b.size 

          shortest_edit.each_with_index.reverse_each do |v, d|
            k = x - y

            if k == -d or (k != d and v[k - 1] < v[k + 1])
              prev_k = k + 1
            else 
              prev_k = k - 1
            end

            prev_x = v[prev_k]
            prev_y = prev_x - prev_k

            while x > prev_x and y > prev_y
              yield x - 1, y - 1, x , y 
              x, y = x - 1, y - 1
            end

            yield prev_x, prev_y, x , y if d > 0

            x, y = prev_x, prev_y
          end
        end


        # Implements the core of Myers' diff algorithm to find the shortest edit script
        # Returns a trace of editing steps where:
        # - n, m are the lengths of sequences a and b
        # - d is the number of edits
        # - k is the diagonal number (x - y)
        # - v stores endpoints of furthest reaching D-paths
        def shortest_edit
          n, m = @a.size, @b.size
          max = n + m

          v = Array.new(2 * max + 1)
          v[1] = 0
          trace = []
          
          (0..max).step do |d|
            trace.push(v.clone) # store the snapshots of v
            
            (-d..d).step(2) do |k|
              if k == -d or (k != d and v[k - 1] < v[k + 1])
                x = v[k + 1]
              else 
                x = v[k - 1] + 1
              end
              y = x - k
              
              while x < n and y < m and @a[x].text == @b[y].text
                x, y = x + 1, y + 1
              end

              v[k] = x

              return trace if x >= n and y >= m
            end
          end
        end
        
  end  
end
