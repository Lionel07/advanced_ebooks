require 'twitter_ebooks'

# Moo Bot version 1

#=====================================================================
# Config
#======================================================================

# Bot configuration
BOT_NAME = "" # The bot's handle
OWNER = "" # Your handle
BLACKLIST = ['kylelehk', 'friedrichsays', 'Sudieofna', 'tnietzschequote', 'NerdsOnPeriod', 'FSR', 'BafflingQuotes', 'Obey_Nxme'] # Don't talk to these people
DO_ALERT_OWNER = true # Allow the bot to alert the owner of errors
ALLOW_COMMANDS = true # Allow's the Owner to send the bot commands

# Twitter Authentication
# All self explanatory. Make an app and get the information from the BOTS account.
ACCESS_TOKEN = ""
ACCESS_TOKEN_SECRET = ""
CONSUMER_KEY = ""
CONSUMER_SECRET = ""

# Tweet Settings
DELAY_RANGE = 1..6 # Delay in seconds to respond.
STARTUP_TWEET = false # Do a tweet on startup?
DEFAULT_SCHEDULE = '30m' # Format is number followed by a one letter denominator (3s, 2m, 15m, 30m, 2h, 2d)
DO_FOLLOWER_PARITY = true # Adjust your followers while the bot is running
DO_FOLLOWER_PARITY_ONSTARTUP = true # Adjust your followers while the bot is starting
FOLLOW_PARITY_SCHEDULE = '0 */2 * * *' # A cron time string determining how often Follower parity is done, if enabled

# Pester Settings
PESTER_ALLOW = true # Allow the bot to mention / retweet / like to users that have mentioned it.
PESTER_ALLOW_RETWEET = true
PESTER_ALLOW_LIKE = true
PESTER_ALLOW_REPLY = true

# Very interesting = Contains words in the top 20 words. Values are %'s out of 1.0. Set to 0 to disable
PESTER_ENABLE_VERYINTERSTING = true
PESTER_RATE_VERYINTERESTING_LIKE = 0.5
PESTER_RATE_VERYINTERESTING_RETWEET = 0.1
PESTER_RATE_VERYINTERESTING_REPLY = 0.1
# Interesting = Contains words in the top 100 words. Values are %'s out of 1.0. Set to 0 to disable.
PESTER_ENABLE_INTERESTING = true
PESTER_RATE_INTERESTING_LIKE = 0.05
PESTER_RATE_INTERESTING_RETWEET = 0.01
PESTER_RATE_INTERESTING_REPLY = 0.001
# END CONFIG

# Information about a particular Twitter user we know
class UserInfo
  attr_reader :username

  # @return [Integer] how many times we can pester this user unprompted
  attr_accessor :pesters_left

  # @param username [String]
  def initialize(username)
    @username = username
    @pesters_left = 1
  end
end

class Ebooks::TweetMeta
  def is_retweet?
    tweet.retweeted_status? || !!tweet.text[/[RM]T ?[@:]/i]
  end
end

class AdvancedBot < Ebooks::Bot
  attr_accessor :original, :model, :model_path, :schedule

  def configure
    # Configuration for all CloneBots
    @userinfo = {}
  end

  def hasSetSchedule; @hasSetSchedule ||= false; end
  def top100; @top100 ||= model.keywords.take(100); end
  def top20;  @top20  ||= model.keywords.take(20); end

  def on_startup
    load_model!
    log "Starting up!"

    if STARTUP_TWEET == true
      log "Making startup tweet..."
      tweet("(Updated / Rebooted): " + model.make_statement)
    end

    def scheduler.on_error(job, error)
      msg = "Scheduler intercepted error in job #{job.id}: #{error.message}"
      alert_owner(msg)
    end

    if DO_FOLLOWER_PARITY_ONSTARTUP == true
      follow_parity
    end

    set_schedule(DEFAULT_SCHEDULE)

    if DO_FOLLOWER_PARITY == true
      scheduler.cron '0 */2 * * *' do
        follow_parity
      end
    end

  end

  def on_message(dm)
    is_command = dm.sender.screen_name == @original && dm.text.start_with?('!') && ALLOW_COMMANDS
    if is_command 
      run_command(dm.text[1..-1])
    else
      delay do
        reply(dm, model.make_response(dm.text))
      end
    end
  end

  def run_command(command)
    log "Running command: #{command}"
    case command
      when /^pause/i
        @schedule.pause
        alert_owner "Tweeting has been paused."
      when /^resume/i
        @schedule.resume
        alert_owner "Tweeting has been resumed."
      when /^force-burst ([^ ]+)/i
        irritator = $1.to_i
        while irritator > 0
          alert_owner "Tweets left: " + irritator.to_s
          irritator-=1
          delay do
            tweet = twitter.update(model.make_statement)
          end
        end
        alert_owner "Tweets left: 0. Done"
      when /^topic (.*)/i
        tweet = twitter.update(model.make_response($1))
        alert_owner "I tweeted! #{tweet.url}"
      when /^force/i
        tweet = twitter.update(model.make_statement)
        alert_owner "I tweeted! #{tweet.url}"
      when /^say (.*)/i
        twitter.update($1)
      when /^mention (.[^ ]*)/i
        tweet = twitter.update("@" + $1 + " " + model.make_statement)
        alert_owner "I mentioned! #{tweet.url}"
      when /^mention-respond (.[^ ]*) (.*)/i
        tweet = twitter.update("@" + $1 + " " + model.make_response($2))
        alert_owner "I mentioned! #{tweet.url}"
      when /^every ([^ ]+)/i
        set_schedule($1)
      when /^next/i
        alert_owner("Next tweet is scheduled for:", @schedule.next_time)
      when /^help/i
        alert_owner("Commands: pause / resume, force(-burst), every (x), next, count, mention(-respond), say, uptime, top (x), delete (last|x), block (x)")
      when /^count/i
        alert_owner("Scheduler has tweeted", @schedule.count, "times.")
      when /^uptime/i
        alert_owner(scheduler.uptime_s, "since", scheduler.started_at)
      when /^top 20/i
        alert_owner(top20)
      when /^top 100/i
        alert_owner(top100)
      when /^delete/i
        delete_tweet( $'.scan(/last|\d+/i).map{ |id| id.upcase == "LAST" ? last_tweet.id : id } )
      when /^block/i
        block_user( $'.scan(/[^ ]+/) )
      else 
        alert_owner "Unrecognized command: #{command}"
    end
  end

  def on_mention(tweet)
    # Become more inclined to pester a user when they talk to us
    userinfo(tweet.user.screen_name).pesters_left += 1

    delay do
      reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
    end
  end

  def on_timeline(tweet)
    return if tweet.retweeted_status?
    return unless can_pester?(tweet.user.screen_name)

    tokens = Ebooks::NLP.tokenize(tweet.text)

    interesting = tokens.find { |t| top100.include?(t.downcase) }
    very_interesting = tokens.find_all { |t| top20.include?(t.downcase) }.length > 2

    delay do
      if very_interesting
        favorite(tweet) if rand < PESTER_RATE_VERYINTERESTING_LIKE && PESTER_ALLOW_LIKE
        retweet(tweet) if rand < PESTER_RATE_VERYINTERESTING_RETWEET && PESTER_ALLOW_RETWEET
        if rand < PESTER_RATE_INTERESTING_REPLY && PESTER_ALLOW_REPLY
          userinfo(tweet.user.screen_name).pesters_left -= 1
          reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
        end
      elsif interesting
        favorite(tweet) if rand < PESTER_RATE_INTERESTING_LIKE && PESTER_ALLOW_LIKE
        retweet(tweet) if rand < PESTER_RATE_INTERESTING_RETWEET && PESTER_ALLOW_RETWEET
        if rand < PESTER_RATE_VERYINTERESTING_REPLY && PESTER_ALLOW_REPLY
          userinfo(tweet.user.screen_name).pesters_left -= 1
          reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
        end
      end
    end
  end

  # Find information we've collected about a user
  # @param username [String]
  # @return [Ebooks::UserInfo]
  def userinfo(username)
    @userinfo[username] ||= UserInfo.new(username)
  end

  # Check if we're allowed to send unprompted tweets to a user
  # @param username [String]
  # @return [Boolean]
  def can_pester?(username)
    userinfo(username).pesters_left > 0 && PESTER_ALLOW
  end

  # Only follow our original user or people who are following our original user
  # @param user [Twitter::User]
  def can_follow?(username)
    @original.nil? || username == @original || twitter.friendship?(username, @original)
  end

  def favorite(tweet)
    if can_follow?(tweet.user.screen_name)
      super(tweet)
    else
      log "Unfollowing @#{tweet.user.screen_name}"
      twitter.unfollow(tweet.user.screen_name)
    end
  end

  def on_follow(user)
    if can_follow?(user.screen_name)
      follow(user.screen_name)
    else
      log "Not following @#{user.screen_name}"
    end
  end

  def last_tweet
    twitter.user_timeline(username, count: 1, exclude_replies: true)[0]
  end

  def delete_tweet(tweets)
    return if tweets.empty?
    begin
      twitter.destroy_tweet(tweets)
    rescue Twitter::Error => e
      alert_owner "Error: #{e.message}"
    else
      alert_owner "Deleted tweet(s) #{tweets.join(', ')}."
    end
  end

  private
  def load_model!
    return if @model

    @model_path ||= "model/#{original}.model"

    log "Loading model #{model_path}"
    @model = Ebooks::Model.load(model_path)
  end

  def catch_twitter
    begin
      yield
    rescue Twitter::Error => error
      @retries += 1
      raise if @retries > @max_error_retries
      if error.class == Twitter::Error::TooManyRequests
        reset_in = error.rate_limit.reset_in
        log "RATE: Going to sleep for ~#{reset_in / 60} minutes..."
        sleep reset_in
        retry
      elsif error.class == Twitter::Error::Forbidden
        # don't count "Already faved/followed" message against attempts
        @retries -= 1 if error.to_s.include?("already")
        log "WARN: #{error.to_s}"
        return true
      elsif ["execution", "capacity"].any?(&error.to_s.method(:include?))
        log "ERR: Timeout?\n\t#{error}\nSleeping for #{@timeout_sleep} seconds..."
        sleep @timeout_sleep
        retry
      else
        log "Unhandled exception from Twitter: #{error.to_s}"
        raise
      end
    end
  end

  def unfollow(user, *args)
    log "Unfollowing #{user}"
    catch_twitter { twitter.unfollow(user, *args) }
  end
  #------------------------------------------------------------
  # follow_parity: Checks to make sure everyone who should be
  # followed is followed.
  #------------------------------------------------------------
  def follow_parity
    followers = catch_twitter { twitter.followers(:count=>200).map(&:screen_name) }
    following = catch_twitter { twitter.following(:count=>200).map(&:screen_name) }
    to_follow = followers - following
    to_unfollow = following - followers
    catch_twitter { twitter.follow(to_follow) } unless to_follow.empty?
    catch_twitter { twitter.unfollow(to_unfollow) } unless to_unfollow.empty?
    @followers = followers
    @following = following - to_unfollow
    if !(to_follow.empty? || to_unfollow.empty?)
      log "Followed #{to_follow.size}; unfollowed #{to_unfollow.size}."
    end
  end
  #------------------------------------------------------------
  # alert_owner: Alerts the owner via DM
  #------------------------------------------------------------
  def alert_owner(*args)
    return if !DO_ALERT_OWNER
    msg = args.map(&:to_s).join(' ')
    log "Alert:", msg
    twitter.create_direct_message(@original, msg) unless @original.nil?
  end

  # Scheduling Stuff

  def set_schedule(interval)
    @schedule.unschedule if @schedule
    @schedule = scheduler.every interval.to_s, :job => true do
      # Every interval [String], post a single tweet
      tweet(model.make_statement)
    end
    if hasSetSchedule == true
      alert_owner "Now tweeting every #{@schedule.original}."
    end

    hasSetSchedule = true
  end

end

AdvancedBot.new(BOT_NAME) do |bot|
  bot.access_token = ACCESS_TOKEN
  bot.access_token_secret = ACCESS_TOKEN_SECRET
  bot.consumer_key = CONSUMER_KEY
  bot.consumer_secret = CONSUMER_SECRET
  bot.blacklist = BLACKLIST
  bot.delay_range = DELAY_RANGE
  bot.original = OWNER
end