#!/usr/bin/ruby
require 'rubygems'; require 'active_support/all'
require 'nokogiri'; require 'open-uri'; require 'chronic'
require 'yaml'
require 'net/http'

THREADS_STORE_YAML = "var/threads.yaml"
DATA_STORE = "data/raw/"
SLEEP = true
STARTER = Time.now

def merge_thread_urls(index_file_name)
  stored_threads = read_threads_store()
  index_time = parse_file_time(index_file_name)
  current_threads = get_thread_urls(index_file_name, index_time)
  merged_threads = current_threads.merge(stored_threads)
  merged_threads.each_pair do |key, thread|
    if !thread[:off_index_time] and !current_threads[key]
      thread[:off_index_time] = index_time.to_i
    end
  end
  store_threads(merged_threads)
end

# Gets threads if they've been off the homepage for a day
def harvest_final_threads
  threads = read_threads_store()
  last_census = (1.day.ago.to_i - 30.minutes).to_i
  threads.each_pair do |key, thread|
    if thread[:off_index_time] and thread[:off_index_time] < last_census
      fetch_thread("final", thread[:id])
      threads.delete(key)
    end
  end
  store_threads(threads)
end

### Helper functions

# Reads the threads from an index
# Returns an array
def get_thread_urls(file_name, index_time)
  doc = Nokogiri::HTML(open(file_name))
  thread = nil
  threads = {}
  doc.css('table table tr').each do |row|
    story = row.at_css('td.title a')
    if story
      thread = {}
      thread[:title] = story.content
      thread[:on_index_time] = index_time.to_i
    end
    row.css('td.subtext a').each do |sub_link|
      if sub_link[:href] =~ /^item\?id=(\d+)/
        thread_id = $1
        thread[:id] = thread_id.to_i
        threads[thread_id] = thread
      end
    end
  end
  return threads
end

def read_threads_store
  if File.exists?(THREADS_STORE_YAML)
    threads = YAML.load(open(THREADS_STORE_YAML))
  else
    threads = {}
  end
end

def store_threads(threads)
  open(THREADS_STORE_YAML, "w") { |file| file.write(threads.to_yaml) }
end

def fetch_newcomments(infix = nil)
  if infix
    infix = '_' + infix
  else
    infix = ''
  end
  fetch("http://news.ycombinator.com/newcomments", "newcomments" + infix)
end

def fetch_thread(infix, thread_id)
  return fetch('http://news.ycombinator.com/item?id=' + thread_id.to_s,
      'thread' + '_' + infix + '_' + thread_id.to_s)
end

def fetch(url, file_prefix)
  before = Time.now
  resp = Net::HTTP.get(URI.parse(url))
  after = Time.now
  time = before + ((after - before) / 2.0)
  file_name = DATA_STORE + file_prefix + '_' + time.to_i.to_s + '.html'
  open(file_name, "w") { |file|
    file.write(resp)
  }
  sleep 30 + rand(21) if SLEEP
  return file_name
end

def parse_file_time(file_name)
  return Time.at(file_name.split('_')[-1].split('.')[0].to_i)
end

def sleep_past_starter(time)
  if STARTER > time.ago
    sleep (time.to_i - (Time.now - STARTER).to_i) if SLEEP
  end 
end

# Invokes the script. Either scrape or send (./scraper.rb scrape)
if ARGV[0] == "eeep"
  fetch_newcomments("eeep") # 0
  sleep_past_starter(8.minutes)
  fetch_newcomments("eeep") # 10
  sleep_past_starter(18.minutes)
  fetch_newcomments("eeep") # 20
  sleep_past_starter(28.minutes)
  fetch("http://news.ycombinator.com/", "index_eeep")
  fetch("http://news.ycombinator.com/newest", "newest_eeep")
  sleep_past_starter(38.minutes)
  fetch_newcomments("eeep") # 40
elsif ARGV[0] == "grun"
  fetch_newcomments("grun") # 0
  sleep_past_starter(8.minutes)
  fetch_newcomments("grun") # 10
  sleep_past_starter(18.minutes)
  fetch_newcomments("grun") # 20
  sleep_past_starter(28.minutes)
  fetch("http://news.ycombinator.com/", "index_grun")
  fetch("http://news.ycombinator.com/newest", "newest_grun")
  sleep_past_starter(38.minutes)
  fetch_newcomments("grun") # 40
else
  index_file_name = fetch("http://news.ycombinator.com/", "index")
  fetch("http://news.ycombinator.com/newest", "newest")
  merge_thread_urls(index_file_name)
  harvest_final_threads()
  sleep_past_starter(30.minutes)
  fetch_newcomments() # 30
  sleep_past_starter(50.minutes)
  fetch_newcomments() # 50
end
