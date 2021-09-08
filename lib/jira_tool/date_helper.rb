require 'dotiw'

module JiraTool
  class DateHelper
    class << self
      include DOTIW::Methods

      def difference_in_words(date)
        distance_of_time_in_words(Time.current, date.to_datetime, highest_measure_only: true)
      end

      def ago(date)
        difference_in_words(date) + ' ago'
      end

      def weekdays_until(date)
        return nil if date.nil?

        date = date.to_date
        date = date.prev_weekday unless date.on_weekday?
        d = Date.current
        i = 0
        until d >= date
          d = d.next_weekday
          i += 1
        end
        i
      end
    end
  end
end
