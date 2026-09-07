require "csv"
require "json"
require "stringio"
require "zlib"

module MetricCapture
  def self.append(file, request)
    body = request.body
    encoding = request.headers.find { |name, _| name.downcase == "content-encoding" }&.last
    body = Zlib::GzipReader.wrap(StringIO.new(body), &:read) if encoding == "gzip"
    CSV.open(file, "a") do |csv|
      csv << [Time.now.to_s, body, request.headers.to_json]
    end
  end
end
