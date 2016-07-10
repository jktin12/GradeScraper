require 'nokogiri'
require 'http'
require 'highline/import'
require 'pry-byebug'

# CONSTANTS #
CULEARN_HYPHEN = '–'.freeze # this is a different hyphen than a regular one
                            # had to copy and paste from CULearn

# GLOBAL #
$cookies = {}

def login_success?(response)
  response.uri.to_s.include? 'testsession'
end

def success?(response)
  (200...300).cover? response.code # useless, CULearn always gives 200 OK
end

def perform_login_redirect(html)
  page = Nokogiri::HTML(html)
  HTTP.get(page.css('a')[0]['href'])
end

def login
  login_success = false
  until login_success
    username = ask('Username: ')
    password = ask('Password: ') { |q| q.echo = false }
    puts "Attempting to log into CULearn as user [ #{username} ]"
    login_response = HTTP.post(
      'https://culearn.carleton.ca/moodle/login/index.php',
      form: { username: username, password: password, Submit: 'login' }
    )
    response = perform_login_redirect(login_response.to_s)
    login_success = success?(response)
    puts login_success ? 'Login successful' : 'Login failed. Please try again.'
  end
  return login_response.headers['Set-Cookie'] if login_success
  :abort # otherwise abort
end

def get_courses_page
  response = HTTP.cookies($cookies).get(
    'https://culearn.carleton.ca/moodle/my/'
  )
  if success?(response)
    puts 'Courses page retrieved'
    return Nokogiri::HTML(response.to_s)
  else
    puts "Fetch failed with Code: #{response.code} Data: #{response}"
  end
end

def get_grade_report(course_id)
  response = HTTP.cookies($cookies).get(
    'https://culearn.carleton.ca/moodle/grade/report/user/index.php',
    params: { id: course_id }
  )
  if success?(response)
    puts 'Grade report retrieved'
    return Nokogiri::HTML(response.to_s)
  else
    puts "Fetch failed with Code: #{response.code} Data: #{response}"
  end
end

####### Program Start ##########


# num_semesters = ask('# Semesters: ')
item_max_width = 40 # width of output column for grade item name

puts 'CULearn Grade Scraper'
set_cookies = login
if set_cookies == :abort
  puts 'Aborting'
  return
end
set_cookies.each do |variable|
  x = variable.split(' ')[0].split('=')
  $cookies[x[0]] = x[1].chomp(';') if x[0].eql? 'MoodleSession'
end
courses = []
puts 'Retrieving course list...'
courses_page = get_courses_page
courses_page.css('.courses .course').each do |course|
  courses.push course.css('a')[0]['href'].split('?id=')[1] # get id from url params
end
puts 'Displaying grades'
puts ''
courses.each do |course_id|
  grade_page = get_grade_report(course_id)
  if grade_page.xpath('//text()').to_s.include? 'Grader report'
    puts 'TA course: skipped'
    puts ''
    next
  end
  grade_page.css('.generaltable.user-grade tbody tr').each_with_index do |grade_item, i|
    next if grade_item.css('th.column-itemname').to_s.strip == '' # if CULearn has an empty tr for some reason
    if i.zero?
      puts "\nCourse: " + grade_item.css('th.column-itemname').text
      printf "%-#{item_max_width}s %s\n", 'Name', 'Grade'
    else
      name = grade_item.css('th.column-itemname').text
      printf "%-#{item_max_width}s", name[0..item_max_width-2]
      print grade_item.css('td.column-grade').text
      range = grade_item.css('td.column-range').text
      if range.strip != ''
        if range.split(CULEARN_HYPHEN).empty?
          print 'NA'
        else
          # print "|#{range}|"
          # print "~~#{range.split(CULEARN_HYPHEN)}~~"
          print '/' + range.split(CULEARN_HYPHEN).last
        end
      end
      puts ''
    end
  end
  puts ''
end
puts 'Finished'
