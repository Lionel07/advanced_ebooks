Advanced Ebooks
=======================================================

Welcome to the Repo for the Advanced Ebooks bot, a bot of cobbled together features that's meant to be easily configurable.

Features
--------------------------------------------------------
* Easy configuration
* Owner Alerts
* Blacklists
* Configurable Delay between tweets
* Flexible Scheduling
* Follower Parity
* Tweet on Startup
* Fine grained pester control (Allow / Disallow liking, retweeting, and replying)
* Bot commands (Make it say whatever, make it mention people, change how often it tweets)

Setup
--------------------------------------------------------
0. Make sure you've know how twitter_ebooks works, and have it installed!
1. Fill out all the configuration settings in bots.rb to your liking.
2. Make sure the twitter configuration settings are filled out. They're for your bot's app on dev.twitter.com, not the authors account.
3. Edit update-corpus and update-model to include the author's twitter handle, exactly how it appears on Twitter (minus @)
4. Run Update-Corpus and Update-Model. When it asks, give it the same info you used in bots.rb
5. ebooks start!