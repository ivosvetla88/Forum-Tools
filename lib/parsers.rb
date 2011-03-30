require 'forum_tools'
require 'active_support/all'
require 'nokogiri'
require 'chronic'
require 'yaml'
require 'open_struct_array'

class HNParser < OpenStructArray
  def self.all(class_const, file_regexp)
    super(class_const,
        ForumTools::CONFIG[:env_dir] + ForumTools::CONFIG[:raw_dir] + file_regexp)
  end

  def initialize(file_name)
    super(file_name)
    set_correction()
    self.save_time = self.parse_file_time(@file_name)
    return self
  end

  def set_correction
    if @file_name =~ /_grun_/
      @correction = (3.minutes + 4.seconds).to_i * -1
    elsif @file_name =~ /_eeep_/
      @correction = (3.minutes).to_i * -1
    else
      @correction = 0
    end
  end

  def parse_title_line(title_line)
    line = title_line.content.to_s
    data = {}
    if title_line and !line.empty?
      links = 0
      title_line.css('a').each do |sub_link|
        if sub_link[:href] =~ /^user\?id=(.+)/
          user_id = $1
          data[:user] = user_id
        elsif sub_link[:href] =~ /^item\?id=(\d+)/ and links < 2
          post_id = $1
          data[:id] = post_id.to_i
        end
        links += 1
      end
      if data[:id]
        line =~ /^((-|)\d+)/
        points = $1
        raise 'Missing score in file ' + @file_name + ': ' + line if !points
        data[:rating] = points.to_i
        line =~ /(\d+\s+\w+\s+ago)\s+\|/
        time_ago = $1
        raise 'Missing time in file ' + @file_name + ': ' + line if !time_ago
        data[:time_string] = time_ago
        data[:time] = Chronic.parse(time_ago, :now => @save_time).to_i + @correction
        return data
      end
    end
    return false
  end

  def read_html
    return Nokogiri::HTML(open(
        ForumTools::CONFIG[:env_dir] + ForumTools::CONFIG[:raw_dir] + @file_name))
  end

  def parse_file_time(file_name)
    return file_name.split('_')[-1].split('.')[0].to_i + @correction
  end
end

class HNThreadParser < HNParser
  def self.all
    return HNParser.all(HNThreadParser, "thread_final*")
  end

  def initialize(file_name)
    super(file_name)
    doc = self.read_html()
    i = 0
    thread_title = doc.at_css('td.title a')
    if thread_title
      self.title_string = thread_title.content.to_s.strip
      if @title_string =~ /^Poll/
        self.type = "poll"
      elsif @title_string =~ /^Ask/
        self.type = "ask"
      else
        self.type = "normal"
      end
    else # deleted thread
      return false
    end

    title_line = doc.at_css('td.subtext')
    self[i] = {:indent => 0}
    self[i].merge!(parse_title_line(title_line))
    i += 1

    doc.css('table table table').each do |post|
      space_img = post.at_css('td>img')
      self[i] = {}
      if space_img
        self[i][:indent] = space_img[:width].to_s.to_i / 40 + 1
      else
        self[i][:indent] = 0
      end
      body = post.at_css('td.default')
      if body
        title_line = body.at_css('span.comhead')
        title_hash = parse_title_line(title_line)
        if title_hash
          self[i].merge!(parse_title_line(title_line))
          i += 1
        else # post was deleted or is part of poll
          self.pop
        end
      end
    end
    return self
  end

  def save
    file_name = @file_name.gsub("thread_final", "thread")
    file_name.gsub!(/_\d+.html/, ".yaml")
    ForumTools::File.save_yaml(file_name, self)
  end
end

class HNCommentsParser < HNParser
  def self.all
    return HNParser.all(HNCommentsParser, "newcomments*")
  end

  def initialize(file_name)
    super(file_name)
    doc = self.read_html()
    i = 0
    doc.css('td.default').each do |post|
      title_line = post.at_css('span.comhead')
      self[i] = parse_title_line(title_line)
      i += 1
    end
    return self
  end
end

class HNIndexParser < HNParser
  def self.all(file_regexp)
    return HNParser.all(HNIndexParser, file_regexp)
  end

  def initialize(file_name)
    super(file_name)
    doc = self.read_html()
    i = 0
    doc.css('td.subtext').each do |title_line|
      title_hash = parse_title_line(title_line)
      if title_hash
        self[i] = title_hash
        i += 1
      end
    end
    return self
  end
end

class HNUserParser < HNParser
  def self.all
    return HNParser.all(HNUserParser, "user*")
  end

  def initialize(file_name)
    super(file_name)
    hash = {}
    doc = self.read_html()
    i = 0
    doc.css('table form table tr').each do |aspect|
      if i < 4
        key = nil
        aspect.css('td').each do |key_val|
          if key.nil?
            key = key_val.content.gsub(/:$/,'')
          else
            hash[key.to_sym] = key_val.content
          end
        end
      end
      i += 1
    end
    self.signup_time = Chronic.parse(hash[:created], :now => @save_time).to_i + @correction
    self.user = hash[:user]
    self.karma = hash[:karma].to_i
    self.average_rating = hash[:avg].to_f
    return self
  end

  def save
    file_name = @file_name.gsub("user_grun_", "user_")
    file_name.gsub!(/_\d+.html/, ".yaml")
    ForumTools::File.save_yaml(file_name, self)
  end
end
