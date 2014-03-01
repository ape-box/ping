
# Setup
require 'erubis'
require 'digest'

require 'sinatra'
require 'sinatra/cookies'

require 'data_mapper'
require 'time'

pwd = File.realpath File.dirname(__FILE__)
dbf = "#{pwd}/data.base"

# Setup db
DataMapper.setup(:default, "sqlite3://#{dbf}")
class Stamp
    include DataMapper::Resource
    property :userid, String, :required => true, :key => true
    property :time, DateTime, :required => true, :key => true
end
class Session
    include DataMapper::Resource
    property :id, Serial
    property :userid, String
    property :token, String, :required => true, unique: true
    property :ipaddress, String, :required => true
    property :expire, DateTime, :required => true
    property :data, String
end
class User
    include DataMapper::Resource
    property :id, Serial
    property :login, String, :required => true
    property :secret, String, :required => true
end
DataMapper.finalize

unless File.file?(dbf)
    DataMapper.auto_migrate!
    DataMapper.auto_upgrade!
end

# Helpers
def user
    @user_buffer = User.first(:id => get_session[:userid]) if @user_buffer.nil?

    return @user_buffer
end
def user_create(val)
    u = User.new
    u.login = val[:login]
    u.secret = val[:secret]

    u.save
    return u
end

def token
    if cookies[:token].nil?
        cookies[:token] = Digest::SHA2.base64digest(Time.now.to_s + Random.rand.to_s)
    end
    cookies[:token]
end

def get_session
    Session.first_or_create(
        {:token => token, :ipaddress => request.ip, :expire.gt => DateTime.now},
        {:token => token, :ipaddress => request.ip, :expire => DateTime.now+1}
    )
end

def set_session(val)
    s = Session.first_or_create(
        {:token => token, :ipaddress => request.ip, :expire.gt => DateTime.now},
        {:token => token, :ipaddress => request.ip, :expire => DateTime.now+1}
    )

    s.userid = val[:userid]
    s.token = val[:token]
    s.ipaddress = val[:ipaddress]
    s.expire = val[:expire]
    s.data = val[:data]
    s.save
end

def userid(usr)
    Digest::SHA2.base64digest(
        Digest::SHA2.base64digest(usr[:login])+
        Digest::SHA2.base64digest(usr[:secret])
    )
end

# Enable Settings
set :erb, :escapt_html => true
set :port, 8080

before do
    @user = user.nil? ? nil : user[:login]
end

# Index
get '/' do
    erb :index
end

# Login
post '/' do
    if user.nil?
        u = user_create({:login => params[:email],
                         :secret => params[:secret]})

        s = get_session
        s[:userid] = u[:id]
        set_session(s)
    end

    erb :index
end

# Stamping
get '/ping' do
    redirect to("/", 401) if user.nil?

    timestamp = Time.now
    Stamp.create userid: user.id, time: timestamp

    erb :ping, :locals => {:timestamp => timestamp}
end

# Summarizing
get '/pong'  do
    redirect to("/", 401) if user.nil?

    rows = Stamp.all :userid => user[:id]
    dataset = Hash.new

    rows.each do |row|
        time = row.time.to_time
        tkey = time.strftime "%Y-%m-%d"

        unless dataset.has_key? tkey
            dataset[tkey] = [time, Array.new, 0]
        end

        dataset[tkey][1].push row
    end

    dataset.each do |k, v|
        hours = 0.0
        dataset[k][1].each_index do |i|
            if i > 0 and i.odd?
                a = dataset[k][1][i-1].time.to_time
                b = dataset[k][1][i].time.to_time
                hours = hours + ((b - a) / 3600)
            end
        end
        dataset[k][2] = hours
    end

    erb :pong, :locals => {:dataset => dataset}
end

# Errors
not_found do
    "<html><body><h1>404</h1><p>Page Not Found</p></body></html>"
end

error do
    "<html><body><h1>500</h1><p>Internal server Error</p></body></html>"
end
