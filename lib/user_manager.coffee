module.exports = class UserManager

    UserManager.new = (options) -> new UserManager options

    constructor: (options) ->
        throw new Error 'controller is null or undefined' if not options?.controller?
        throw new Error 'bot is null or undefined' if not options?.bot?

        @controller = controller
        @bot = bot

    getLocalUser: (opts, cb) ->
        @controller.storage.users.get opts.user, (err, user) ->
            if err
                @bot.botkit.log('Failed to get local user data.', err)

            cb null, user

    getSlackUser: (opts, cb) ->
        @bot.api.users.info
            user: opts.user
        , (err, response) ->
            if err
                @bot.botkit.log('Failted to get user data from slack.', err)

            user =
                id: opts.user
                username: response.user.name
                realName: response.user.real_name
                userLink: "<@#{opts.user}|#{response.user.name}>"

            cb null, user

    isUserAdmin: (opts) ->
        opts.username in config.admins

    saveUser: (opts, cb) ->
        @controller.storage.users.save
            id: opts.user
            status: opts.status
            username: opts.username
            realName: opts.realName
            userLink: opts.userLink
            reg: opts.reg
            recentWins: opts.recentWins
        , (err) ->
            cb err

    addUserFromSlack: (opts, cb) ->
        data = {}

        getSlackUser = (next) =>
            @getSlackUser {user: opts.user}, (err, user) ->
                if err
                    return next err

                data.user = user

        saveUser = (next) =>
            @saveUser
                @controller.storage.users.save
                    id: opts.user
                    status: 'ACTIVE'
                    username: data.user.name
                    realName: data.user.real_name
                    userLink: "<@#{opts.user}|#{data.user.name}>"
                    reg: opts.reg
                    recentWins: []
                , (err) ->
                    if err
                        return cb err
