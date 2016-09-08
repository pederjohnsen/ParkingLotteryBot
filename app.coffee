_ = require('underscore')
moment = require('moment')
async = require('async')
Botkit = require('botkit')

config = require('./config')

controller = Botkit.slackbot(
    debug: config.debug
    json_file_store: './data'
)

bot = controller.spawn(
    token: config.slackBotToken
)

bot.startRTM (err, bot, payload) ->
    if err
        throw new Error 'Could not connect to Slack'

    controller.hears ['\\bhello\\b', '\\bhi\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        controller.storage.users.get message.user, (err, user) ->
            if err
                bot.botkit.log('Failed to get user data.', err)

            if user
                bot.reply message, "Hello #{user.userLink}!"
            else
                bot.reply message, 'Hello!'

    controller.hears ['\\bhelp\\b', '\\binfo\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        bot.startConversation message, (err, convo) ->
            if err
                bot.botkit.log('Failed to start conversation.', err)
            else
                convo.say "I'm the parking lottery bot."
                convo.say "You can join by typing 'join @parkinglottery' & leave by typing 'leave @parkinglottery'."
                convo.say "Typing 'current @parkinglottery' tells you the current weeks winners, typing 'upcoming @parkinglottery' tells you the upcoming weeks winners."

    controller.hears ['\\bjoin\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
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
                    attachment =
                        fallback: "You've already joined the Parking Lottery!"
                        text: "You've already joined the Parking Lottery!"
                        color: 'warning'

                    emoji = 'suspect'
                else if data.user?.status is 'INACTIVE'
                    attachment =
                        fallback: "Welcome back to the Parking Lottery <@#{message.user}>!\nYou'll be automatically entered to win a parking space every week."
                        title: "Welcome back to the Parking Lottery <@#{message.user}>!"
                        text: "You'll be automatically entered to win a parking space every week."
                        color: 'good'

                    emoji = 'sunglasses'
                else
                    attachment =
                        fallback: "Welcome to the Parking Lottery <@#{message.user}>!\nYou'll be automatically entered to win a parking space every week."
                        title: "Welcome to the Parking Lottery <@#{message.user}>!"
                        text: "You'll be automatically entered to win a parking space every week."
                        color: 'good'

                    emoji = '+1::skin-tone-2'

                bot.api.reactions.add
                    timestamp: message.ts
                    channel: message.channel
                    name: emoji
                , (err, response) ->
                    if err
                        bot.botkit.log('Failed to add emoji reaction.', err)

                replyWithAttachments =
                    attachments: [attachment]
                    ts: message.ts

                bot.reply message, replyWithAttachments

    controller.hears ['\\bleave\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
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

            if data.user.status is 'INACTIVE'
                attachment =
                    fallback: "You've already been removed from the Parking Lottery!"
                    text: "You've already been removed from the Parking Lottery!"
                    color: 'warning'

                emoji = 'angry'

                bot.api.reactions.add
                    timestamp: message.ts
                    channel: message.channel
                    name: emoji
                , (err, response) ->
                    if err
                        bot.botkit.log('Failed to add emoji reaction.', err)

                replyWithAttachments =
                    attachments: [attachment]
                    ts: message.ts

                bot.reply message, replyWithAttachments

                return next new Error 'User already removed from parking lottery.'

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
                bot.botkit.log('Failed to remove user from parking lottery.', err)
            else
                if !data.user
                    attachment =
                        fallback: "You haven't even joined the Parking Lottery yet!"
                        text: "You haven't even joined the Parking Lottery yet!"
                        color: 'warning'

                    emoji = 'confused'
                else
                    attachment =
                        fallback: "<@#{message.user}>, you've just left the Parking Lottery!\nYou'll need to re-join if you want to win a parking space again."
                        title: "<@#{message.user}>, you've just left the Parking Lottery!"
                        text: "You'll need to re-join if you want to win a parking space again."
                        color: 'good'

                    emoji = 'cry'

                bot.api.reactions.add
                    timestamp: message.ts
                    channel: message.channel
                    name: emoji
                , (err, response) ->
                    if err
                        bot.botkit.log('Failed to add emoji reaction.', err)

                replyWithAttachments =
                    attachments: [attachment]
                    ts: message.ts

                bot.reply message, replyWithAttachments

    controller.hears ['\\bcurrent\\b', '\\bcurrent week\\b', '\\bthis week\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
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

    controller.hears ['\\bnext\\b', '\\bnext week\\b', '\\bupcoming\\b', '\\bupcoming week\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
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

    controller.hears ['\\blist\\b', '\\busers\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        controller.storage.users.all (err, users) ->
            if err
                bot.botkit.log('Error getting users.', err)

            activeUsers = _(users).filter (user) -> user.status is 'ACTIVE'

            if activeUsers.length
                bot.reply message, "There's #{activeUsers.length} #{if activeUsers.length isnt 1 then 'people' else 'person'} in the draw for the parking lottery."
            else
                bot.reply message, "I don't have any data of people in the draw."

    controller.hears ['\\bdraw\\b'], 'direct_mention,mention', (bot, message) ->
        {nextWeek, nextYear} = getNextWeekDates()

        data = {}
        data.alreadyDrawn = false

        bot.startConversation message, (err, convo) ->
            if err
                bot.botkit.log('Failed to start conversation.', err)
            else
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
                    controller.storage.teams.get message.team, (err, team) ->
                        if err
                            bot.botkit.log('Failed to get team data.', err)

                        if !team
                            return next null

                        if _(team.draws).findWhere({week: nextWeek, year: nextYear})
                            bot.botkit.log('Winners have already been drawn for next week.')
                            data.alreadyDrawn = true
                            return next new Error 'Winners have already been drawn for next week.'

                        next null

                drawWinners = (next) ->
                    convo.say "OK! Drawing this upcoming week winners!"
                    draw message, (err, winners) ->
                        if err
                            return next err

                        data.winners = winners
                        next null

                saveDrawOnTeam = (next) ->
                    saveDraw message, (err) ->
                        if err
                            return next err

                        next null                        

                async.waterfall [
                    getCallerUser
                    maybeGetCallerUserFromSlack
                    checkCallerIsAdmin
                    checkIfDrawIsRequired
                    drawWinners
                    saveDrawOnTeam
                ], (err) ->
                    if err
                        bot.botkit.log('Failed to draw winners.', err)

                        if data.user.username not in config.admins
                            convo.say "<@#{message.user}>: You're not an admin!"
                        else if data.alreadyDrawn is true
                            convo.say "Already drawn this upcoming weeks winners!"
                        else
                            convo.say "<@#{message.user}>: I couldn't draw any winners, please try again."
                    else
                        convo.say "<!channel> Hello all! I would like to announce our parking space winners for this coming week...."
                        # If draw winners images are set randomly pick one to post
                        if config.drawWinnersImages.length
                            image = _.sample(config.drawWinnersImages, 1)?[0]
                            # Posting the image as an attachment doesn't look too great, ideally we'd want to add the winners right below the picture.
                            # attachment = {
                            #     attachments: [
                            #         fallback: '...and the winners are...'
                            #         image_url: image
                            #     ]
                            # }
                            # convo.say attachment
                            # Instead lets just post the image url inline and the winners after, the winner names should appear below the image!
                            convo.say "#{image} #{data.winners.join(', ')}."
                        else
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
        async.eachSeries data.winners, (user, cb) ->
            newUser = _.clone(user)
            newUser.recentWins.push {week: nextWeek, year: nextYear}
            controller.storage.users.save newUser, (err) ->
                if err
                    return cb err

                cb null
        , (err) ->
            if err
                bot.botkit.log('Error while saving wins on users.', err)

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

saveDraw = (message, cb) ->
    {nextWeek, nextYear} = getNextWeekDates()

    data = {}

    getTeamData = (next) ->
        controller.storage.teams.get message.team, (err, team) ->
            if err
                bot.botkit.log('Failed to get team data.', err)

            data.team = team
            next null

    saveDrawOnTeam = (next) ->
        if data.team
            newTeamData = _.clone(data.team)
        else
            newTeamData =
                id: message.team
                draws: []

        newTeamData.draws.push {week: nextWeek, year: nextYear}

        controller.storage.teams.save newTeamData, (err) ->
            if err
                bot.botkit.log('Error while saving draw on team.', err)

            next null

    async.waterfall [
        getTeamData
        saveDrawOnTeam
    ], (err) ->
        if err
            cb err
        else
            cb null

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
