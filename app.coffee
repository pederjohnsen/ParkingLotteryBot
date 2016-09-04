_ = require('underscore')
moment = require('moment')
async = require('async')
Botkit = require('botkit')

config = require('./config')

controller = Botkit.slackbot(
    debug: true
    json_file_store: './data'
)

bot = controller.spawn(
    token: 'xoxb-70992350358-Sbav8gt02ufdixeq5MGQx8dg'
)

bot.startRTM (err, bot, payload) ->
    if err
        throw new Error 'Could not connect to Slack'

    controller.hears ['hello', 'hi'], 'direct_message,direct_mention,mention', (bot, message) ->
        controller.storage.users.get message.user, (err, user) ->
            if err
                bot.botkit.log('Failed to get user data.', err)

            if user
                bot.reply message, "Hello #{user.userLink}!"
            else
                bot.reply message, 'Hello!'

    controller.hears ['help', 'info'], 'direct_message,direct_mention,mention', (bot, message) ->
        bot.startConversation message, (err, convo) ->
            if err
                bot.botkit.log('Failed to start conversation.', err)
            else
                convo.say "I'm the parking lottery bot."
                convo.say "You can join by typing 'join @parkinglottery' & leave by typing 'leave @parkinglottery'."
                convo.say "Typing 'current @parkinglottery' tells you the current weeks winners, typing 'upcoming @parkinglottery' tells you the upcoming weeks winners."

    controller.hears ['join'], 'direct_message,direct_mention,mention', (bot, message) ->
        data = {}

        getUser = (next) ->
            controller.storage.users.get message.user, (err, user) ->
                if err
                    bot.botkit.log('Failed to get user data.', err)

                data.user = user
                next null

        addUserIfNotAdded = (next) ->
            if data.user?.status is 'ACTIVE'
                return next null

            bot.api.users.info
                user: message.user
            , (err, response) ->
                if err
                    return next err

                controller.storage.users.save
                    id: data.user?.id or message.user
                    status: 'ACTIVE'
                    username: data.user?.username or response.user.name
                    realName: data.user?.realName or response.user.real_name
                    userLink: data.user?.userLink or "<@#{message.user}|#{response.user.name}>"
                    recentWins: data.user?.recentWins or []
                , (err) ->
                    if err
                        return next err

                    next null

        async.waterfall [
            getUser
            addUserIfNotAdded
        ], (err) ->
            if err
                bot.botkit.log('Failed to add user to parking lottery.', err)
            else
                if data.user?.status is 'ACTIVE'
                    bot.reply message, "You've already joined the parking lottery!"
                else if data.user?.status is 'INACTIVE'
                    bot.reply message, "I've re-entered you into the parking lottery! You don't have to do this again and you'll automatically be entered to win every week."
                else
                    bot.reply message, "I've entered you into the parking lottery! You don't have to do this again and you'll automatically be entered to win every week."

    controller.hears ['leave'], 'direct_message,direct_mention,mention', (bot, message) ->
        data = {}

        getUser = (next) ->
            controller.storage.users.get message.user, (err, user) ->
                if err
                    bot.botkit.log('Failed to get user data.', err)

                data.user = user
                next null

        updateUserIfExists = (next) ->
            if !data.user
                return next null

            newUser = _.clone(data.user)
            newUser.status = 'INACTIVE'
            controller.storage.users.save newUser, (err) ->
                if err
                    return next err

                next null

        async.waterfall [
            getUser
            updateUserIfExists
        ], (err) ->
            if err
                bot.botkit.log('Failed to add user to parking lottery.', err)
            else
                if !data.user
                    bot.reply message, "I can't remove you from the parking lottery as you've yet to join!"
                else
                    bot.reply message, "I've removed you from the parking lottery! You can join back anytime."

    controller.hears ['current', 'this week'], 'direct_mention,mention', (bot, message) ->
        {currentWeek, currentYear} = getCurrentWeekDates()

        controller.storage.users.all (err, users) ->
            if err
                bot.botkit.log('Error getting users.', err)

            currentWinners = _(users)
                .chain()
                .filter (user) ->
                    _(user.recentWins).findWhere({week: currentWeek, year: currentYear})
                .pluck('userLink')
                .value()

            if currentWinners.length
                bot.reply message, "The current winners are: #{currentWinners.join(', ')}."
            else
                bot.reply message, "I don't have any data for this weeks winners."

    controller.hears ['next', 'next week', 'upcoming', 'upcoming week'], 'direct_mention,mention', (bot, message) ->
        {nextWeek, nextYear} = getNextWeekDates()

        controller.storage.users.all (err, users) ->
            if err
                bot.botkit.log('Error getting users.', err)

            upcomingWinners = _(users)
                .chain()
                .filter (user) ->
                    _(user.recentWins).findWhere({week: nextWeek, year: nextYear})
                .pluck('userLink')
                .value()

            if upcomingWinners.length
                bot.reply message, "The upcoming weeks winners are: #{upcomingWinners.join(', ')}."
            else
                bot.reply message, "I don't have any data for the upcoming weeks winners, this could be because the winners haven't been drawn yet!"

    controller.hears ['draw'], 'direct_mention,mention', (bot, message) ->
        {nextWeek, nextYear} = getNextWeekDates()

        data = {}

        getCallerUser = (next) ->
            controller.storage.users.get message.user, (err, user) ->
                if err
                    bot.botkit.log('Failed to get user data.', err)

                data.user = user
                next null

        maybeGetCallerUserFromSlack = (next) ->
            if data.user
                return next null

            bot.api.users.info
                user: message.user
            , (err, response) ->
                if err
                    return next err

                data.user =
                    id: message.user
                    username: response.user.name
                    realName: response.user.real_name
                    userLink: "<@#{message.user}|#{response.user.name}>"

                next null

        checkCallerIsAdmin = (next) ->
            if data.user.username not in config.admins
                return next new Error 'Not admin user!'

            next null

        checkIfDrawIsRequired = (next) ->
            # TODO! - If a draw has already been made, for the coming week, there is no need to do another!
            return next null

        drawWinners = (next) ->
            bot.reply message, "OK! Drawing this upcoming week winners!"
            draw message, (err, winners) ->
                if err
                    return next err

                data.winners = winners
                next null

        async.waterfall [
            getCallerUser
            maybeGetCallerUserFromSlack
            checkCallerIsAdmin
            checkIfDrawIsRequired
            drawWinners
        ], (err) ->
            if err
                bot.botkit.log('Failed to draw winners.', err)

                if data.user.username not in config.admins
                    bot.reply message, "<@#{message.user}>: You're not an admin!"
                else
                    bot.reply message, "<@#{message.user}>: I couldn't draw any winners, please try again."
            else
                bot.startConversation message, (err, convo) ->
                    if err
                        bot.botkit.log('Failed to start conversation.', err)
                    else
                        convo.say "<!channel> Hello all! I would like to announce our parking space winners for this coming week...."
                        convo.say "The winners are: #{data.winners.join(', ')}."

draw = (message, cb) ->
    {nextWeek, nextYear} = getNextWeekDates()

    data = {}

    getEligibleUsers = (next) ->
        controller.storage.users.all (err, users) ->
            if err
                return next err

            data.eligibleUsers = _(users)
                .chain()
                .clone()
                .filter (user) ->
                    # Users can decide to leave the parking lottery
                    if !user.status is 'ACTIVE'
                        return false

                    if !user.recentWins.length
                        return true
                    else
                        async.eachSeries _.range(config.weeksBetweenWins), (week, cb) ->
                            {weekInPast, yearInPast} = getWeekDatesInPast(week)

                            if _(user.recentWins).findWhere({week: weekInPast, year: yearInPast})
                                return cb new Error 'User recently won.'

                            cb null

                        , (err) ->
                            if err
                                bot.botkit.log('User not eligible.', err)
                                return false

                            return true
                .value()

            next null

    drawWinners = (next) ->
        if !data.eligibleUsers.length
            return next new Error 'No eligible users!'

        data.winners = _.sample(data.eligibleUsers, config.parkingSpaces)
        next null

    saveWinsOnUsers = (next) ->
        _(data.winners).each (user) ->
            newUser = _.clone(user)
            newUser.recentWins.push {week: nextWeek, year: nextYear}
            controller.storage.users.save newUser, (err) ->
                if err
                    return next err

                next null

    async.waterfall [
        getEligibleUsers
        drawWinners
        saveWinsOnUsers
    ], (err) ->
        if err
            cb err
        else
            cb null, _(data.winners).pluck('userLink')

getWeekDatesInPast = (weeks) ->
    return {
        weekInPast: moment().subtract(weeks, 'week').week()
        yearInPast: moment().subtract(weeks, 'week').year()
    }

getCurrentWeekDates = ->
    return {
        currentWeek: moment().week()
        currentYear: moment().year()
    }

getNextWeekDates = ->
    return {
        nextWeek: moment().add(1, 'week').week()
        nextYear: moment().add(1, 'week').year()
    }
