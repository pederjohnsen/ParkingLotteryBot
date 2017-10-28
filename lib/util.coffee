moment = require('moment')

getWeekDatesInPast = (weeks) ->
    return {
        weekInPast: moment().subtract(weeks, 'week').week()
        yearInPast: moment().subtract(weeks, 'week').year()
    }

getPreviousWeekDates = ->
    previousWeekDates = getWeekDatesInPast(1)

    return {
        previousWeek: previousWeekDates.weekInPast
        previousYear: previousWeekDates.yearInPast
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

module.exports =
    getWeekDatesInPast: getWeekDatesInPast
    getPreviousWeekDates: getPreviousWeekDates
    getCurrentWeekDates: getCurrentWeekDates
    getNextWeekDates: getNextWeekDates
