# frozen_string_literal: true

module Store
  class Memory
    def initialize
      @data = {}
      @mutex = Mutex.new
    end

    def set(key, value, ttl: nil)
      @mutex.synchronize do
        @data[key] = { value: value, expires_at: ttl ? Time.now + ttl : nil }
      end
    end

    def get(key)
      @mutex.synchronize do
        entry = @data[key]
        return nil unless entry

        if entry[:expires_at] && Time.now > entry[:expires_at]
          @data.delete(key)
          return nil
        end

        entry[:value]
      end
    end

    def delete(key)
      @mutex.synchronize { @data.delete(key) }
    end

    def size
      @mutex.synchronize { @data.size }
    end

    def cleanup
      @mutex.synchronize do
        @data.delete_if { |_, v| v[:expires_at] && Time.now > v[:expires_at] }
      end
    end
  end
end
