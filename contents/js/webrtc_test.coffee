palava = require("palava-client")
async = require("async")
$ = jquery = require('jquery')
require('string-format')

class WebRtcTest

  constructor: (@frontend, cb) ->
    @result = {}
    @errors = []

    @start(cb)

  # helper

  add_error: (text) ->
    @errors.push(text)

  fatal_error: (text, cb) ->
    @add_error(text)

    @frontend.clear()
    @frontend.title("Error")
    @frontend.prompt("Sorry, an error occured: " + text)

    @frontend.add_button "OK", () =>
      cb(new Error(text))

  invite_url: () ->
    return "http://somewhere.com/?r={1}".format(@room_id)

  # start control flow of test

  start: (cb) ->
    # actual flow

    run_test = (invite, wait) =>
      console.log 'running'

      steps = [
        @test_init
        invite
        @test_local
        @test_pc
        wait
        @test_remote
        @test_data
      ]

      done = (err) =>
        if err
          console.log(err)
        @report(cb)

      async.series (fun.bind(@) for fun in steps), done

    # check whether WebRTC is even available

    if palava.browser.checkForWebrtcError()
      @frontend.clear()
      @frontend.title("No WebRTC support")
      @frontend.prompt("Sorry, but your browser does not seem to support WebRTC")

      cb(new Error("No WebRTC support"))

      return

    # ask user which method to use

    @frontend.clear()
    @frontend.title("Test Setup")
    @frontend.prompt("Do you want to test with another person or alone using the echo server?")

    @frontend.add_button "Invite User", () =>
      run_test(
        (cb) => @invite_user(cb)
        (cb) => @wait_user(cb)
      )

    @frontend.add_button "Echo Server", () =>
      run_test(
        (cb) => @invite_echo(cb)
        (cb) => @wait_echo(cb)
      )


  # which test type?

  invite_echo: (cb) ->
    @fatal_error("Test not implemented, yet", cb)


  invite_user: (cb) ->
    html = 'Waiting for other user. Please ask the person you want to test with to visit the following page:<br /><a href="{0}">{0}</a>'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Invite peer")
    @frontend.prompt_html(html)

    @frontend.add_button "Done", () ->
      cb()


  # internal

  test_init: (cb) ->
    cb()
    #cb(new Error("TODO: implement"))


  test_pc: (cb) ->
    @fatal_error("Test not implemented, yet", cb)


  # test streams

  test_local: (cb) ->
    @fatal_error("Test not implemented, yet", cb)


  test_remote: (cb) ->
    @fatal_error("Test not implemented, yet", cb)


  test_data: (cb) ->
    @fatal_error("Test not implemented, yet", cb)


  # waiting for remote
  
  wait_user: (cb) ->
    if @remote_present()
      cb()
      return

    html = 'Waiting for other user. Please ask the person you want to test with to visit the following page:<br /><a href="{0}">{0}</a>'.format(@invite_url())

    @frontend.clear()
    @frontend.title("Waiting for peer")
    @frontend.prompt_html(html)

    # TODO: allow fail ...

    @wait_any(cb)

  
  wait_echo: (cb) ->
    if @remote_present()
      cb()
      return

    @frontend.clear()
    @frontend.title("Contacting Echo Server")
    @frontend.prompt("Waiting for connection with echo server ...")

    # TODO: allow fail ...

    @wait_any(cb)


  remote_present: () ->
    # TODO: implement ...
    return false


  wait_any: (cb) ->
    @fatal_error("Test not implemented, yet")


  # reporting

  report: (cb) ->
    @frontend.clear()
    @frontend.title("Test complete")

    html = "<div>Thanks for testing. Please press the button below to report the results to the developers.</div>"

    if @errors.length
      error_list = $('<ul>')

      for error in @errors
        error_list.append($('<li>').text(error))

      html += error_list.html()
    else
      html += "<div>No errors detected</div>"

    @frontend.prompt_html(html)

    @frontend.add_button "Send report", () =>
      console.log "Reporting ... someday"

      # TODO

      @frontend.clear()
      @frontend.title("Thanks!")
      @frontend.prompt("Thanks for sending the report!")

      cb()


module.exports =
  WebRtcTest: WebRtcTest
