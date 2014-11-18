WebRtcTest = require('./webrtc_test').WebRtcTest
palava = require('palava-client')
$ = juery = require('jquery')

class TestFrontend

  constructor: () ->
    @$title = $('#title')
    @$prompt = $('#prompt')
    @$video = $('#video')
    @$input = $('#input')

    if not @$title or not @$prompt or not @$video or not @$input
      console.log("Incomplete frontend!")

  # empty stuff

  clear: () ->
    @$title.empty()
    @$prompt.empty()
    @$video.empty()
    @$input.empty()

  clear_video: () ->
    @$video.empty()

  clear_input: () ->
    @$input.empty()

  # simple stuff

  title: (text) ->
    @$title.text(text)

  prompt: (text) ->
    @$prompt.text(text)

  prompt_html: (html) ->
    @$prompt.html(html)

  # video stuff

  video: (stream) ->
    dom = $('<video autoplay>')
    @$video.append(dom)
    palava.browser.attachMediaStream(dom, stream)
    dom[0].play()

  # input stuff

  add_button: (text, cb) ->
    dom = $('<button></button>').text(text)
    dom.click(cb)
    @$input.append(dom)

$ () ->
  frontend = new TestFrontend($('body'))
  test = new WebRtcTest frontend, (err) ->
    console.log(err)

