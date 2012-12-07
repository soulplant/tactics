WIDTH = 320
HEIGHT = 240
TILE_WIDTH = 16
TILE_HEIGHT = 16

VKEY_LEFT = 37
VKEY_UP = 38
VKEY_RIGHT = 39
VKEY_DOWN = 40

c = document.createElement 'canvas'
c.width = WIDTH
c.height = HEIGHT
document.body.appendChild c
ctx = c.getContext '2d'

clear = ->
  ctx.clearRect 0, 0, WIDTH, HEIGHT

class EntitySet
  constructor: ->
    @nextId = 0
    @entities = []

  add: (e) ->
    e.id = @nextId++
    @entities.push e

  drawAll: (ctx) ->
    e.draw ctx for e in @entities

  tickAll: ->
    e.tick() for e in @entities

es = new EntitySet

between: (l, x, h) -> l <= x <= h

rectContains: (p1, rect) ->
  between rect.x, p1.x, rect.x + rect.width and
    between rect.y, p1.y, rect.y + rect.height

class Entity
  constructor: ->
    @x = @y = 0
    @width = TILE_WIDTH
    @height = TILE_HEIGHT
    es.add @

  contains: (x, y) ->
    between @x, x, @x + @width and
      between @y, y, @y + @height

  tick: ->
  draw: ->

class GamePiece extends Entity
  constructor: (@tx, @ty, @name) ->
    super()
    @recalcOnscreenPos()
    @age = 0
    @selected = false

  select: -> @selected = true
  deselect: -> @selected = false

  draw: (ctx) ->
    ###
    ctx.fillStyle = 'red'
    ctx.fillRect @x, @y, @width, @height
    ###
    ctx.fillStyle = @name
    ctx.fillRect @x, @y, @width, @height
    if @selected
      ctx.strokeStyle = 'black'
      ctx.strokeRect @x, @y, @width, @height

  moveBy: (pt) ->
    @tx += pt.x
    @ty += pt.y
    @recalcOnscreenPos()

  recalcOnscreenPos: ->
    @x = @tx * TILE_WIDTH
    @y = @ty * TILE_HEIGHT

  tick: ->
    @age++

class Game
  constructor: ->
    m = new GamePiece 0, 0, 'red'
    m1 = new GamePiece 1, 1, 'green'
    @team = [m, m1]
    @nextToMove = 0
    @selected().select()

  receiveInput: (event) ->
    delta = @eventToDir event
    @selected().moveBy delta
    @selectNext()

  selected: ->
    @team[@nextToMove]

  selectNext: ->
    @selected().deselect()
    @nextToMove++
    @nextToMove %= @team.length
    @selected().select()

  eventToDir: (event) ->
    switch event.keyCode
      when VKEY_LEFT then {x:-1, y:0}
      when VKEY_UP then {x:0, y:-1}
      when VKEY_RIGHT then {x:1, y:0}
      when VKEY_DOWN then {x:0, y:1}

  tick: ->

g = new Game

document.addEventListener 'keydown', (e) ->
  g.receiveInput e
, false

gameLoop = ->
  clear()
  es.tickAll()
  es.drawAll ctx
  # console.log 'hi'

id = setInterval gameLoop, (1000/10)

clear()

###
ctx.fillStyle = 'red'
ctx.fillRect 0, 0, 20, 20
console.log ctx
###
