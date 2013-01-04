TILE_WIDTH = 16
TILE_HEIGHT = 16
SCREEN_WIDTH = 320
SCREEN_HEIGHT = 240

VKEY_LEFT = 37
VKEY_UP = 38
VKEY_RIGHT = 39
VKEY_DOWN = 40
VKEY_ENTER = 13
VKEY_SEMICOLON = 186

VKEY_H = 72
VKEY_J = 74
VKEY_K = 75
VKEY_L = 76

# z-index
RADIUS = 0
PIECE = 1
CURSOR = 2

FPS = 60
WALK_TICKS = (FPS/6)
MOVEMENT_RANGE = 5
CURSOR_MOVE_PX = 3

PLAYER_TEAM = 1
ENEMY_TEAM = 2

c = document.createElement 'canvas'
c.width = SCREEN_WIDTH
c.height = SCREEN_HEIGHT
document.body.appendChild c
ctx = c.getContext '2d'

cloneObject = (obj) ->
  result = {}
  for own k of obj
    result[k] = obj[k]
  result

loadImage = (fn) ->
  img = new Image()
  img.src = fn
  img

loadImageDirMap = (name) ->
  imgs = {}
  imgs['left'] = loadImage 'gfx/' + name + '-l.png'
  imgs['right'] = loadImage 'gfx/' + name + '-r.png'
  imgs['up'] = loadImage 'gfx/' + name + '-u.png'
  imgs['down'] = loadImage 'gfx/' + name + '-d.png'
  imgs

fighterImgs = loadImageDirMap 'fighter'
enemyFighterImgs = loadImageDirMap 'efighter'

tileImgs = {}
tileImgs['grass'] = loadImage 'gfx/grass.png'
tileImgs['dirt'] = loadImage 'gfx/dirt.png'

clear = ->
  ctx.clearRect 0, 0, SCREEN_WIDTH, SCREEN_HEIGHT

class EntitySet
  constructor: ->
    @nextId = 0
    @entities = []

  add: (e) ->
    e.id = @nextId++
    @entities.push e

  tick: ->
    e.baseTick() for e in @entities
    @entities = (e for e in @entities when e.alive)

class KeyFocusStack
  constructor: ->
    @stack = []

  push: (entity, cb) ->
    @stack.push {entity, cb, inited:false}

  peek: ->
    throw "empty stack" if @stack.length == 0
    @stack[@stack.length - 1]

  block: (cb) ->
    @push new InputBlocker
    =>
      @pop()
      cb?()

  pop: ->
    pair = @peek()
    @stack.pop()
    pair.cb?()
    pair

  inputUpdated: (controller) ->
    return if @stack.length == 0
    pair = @peek()
    if !pair.inited
      pair.entity.init?()
      pair.inited = true
      # init() might have push()ed, so we re-handle.
      @inputUpdated controller
      return
    if pair.entity.inputUpdated controller
      @pop()

es = new EntitySet
fs = new KeyFocusStack

between: (l, x, h) -> l <= x <= h

rectContains: (p1, rect) ->
  between rect.x, p1.x, rect.x + rect.width and
    between rect.y, p1.y, rect.y + rect.height

class Entity
  constructor: ->
    @x = @y = 0
    @width = TILE_WIDTH
    @height = TILE_HEIGHT
    @alive = true
    @subTickers = []
    es.add @

  contains: (x, y) ->
    between @x, x, @x + @width and
      between @y, y, @y + @height

  kill: ->
    @subTickers = []
    @alive = false

  addSubTicker: (st) ->
    @subTickers.push st

  baseTick: ->
    # Cull dead sub tickers.
    @subTickers = (s for s in @subTickers when s.alive)
    s.tick() for s in @subTickers
    @tick()

  tick: ->
  draw: (ctx) ->

class OptionSelector extends Entity
  MAX_OFFSET = 30
  OFFSET_PPS = FPS / 5
  SLIDE_DURATION = 5

  # @options is an array of choices, in the order left, right, up, down
  constructor: (@options, defaultOption) ->
    super()
    @x = (SCREEN_WIDTH/2 - 16)
    @y = SCREEN_HEIGHT - 16
    @offset = 0
    @zIndex = CURSOR
    @currentChoice = defaultOption or (if @options.length > 2 then @options[3] else @options[0])
    @done = false
    @images = {}
    for option in @options
      @images[option] = loadImage 'gfx/' + option + '-icon.png'

  init: ->
    slideIn = new PositionSlide @, @, ptAdd(@, {x:0, y:-30}), SLIDE_DURATION, fs.block()
    @addSubTicker slideIn

  inputUpdated: (controller) ->
    return true if @done
    if controller.left()
      @currentChoice = @options[0]
    if controller.right()
      @currentChoice = @options[1]
    if controller.up()
      @currentChoice = @options[2]
    if controller.down()
      @currentChoice = @options[3]
    if controller.action() or controller.cancel()
      tookAction = controller.action()
      slideOut = new PositionSlide @, @, ptAdd(@, {x:0, y:30}), SLIDE_DURATION, fs.block =>
        @done = true
        @committed = tookAction
        @kill()
      @addSubTicker slideOut
    false

  tick: ->

  drawBox: (option, x, y, w, h) ->
    img = @images[option]
    ctx.drawImage img, x, y
    if option == @currentChoice
      ctx.strokeStyle = 'black'
      ctx.strokeRect x, y, w, h

  draw: (ctx) ->
    # left box
    @drawBox @options[0], @x - 16, @y, 16, 16
    @drawBox @options[1], @x + 16, @y, 16, 16
    return unless @options.length > 2
    @drawBox @options[2], @x, @y - 16, 16, 16
    @drawBox @options[3], @x, @y + 16, 16, 16

txInPx = (tx, ty) -> {x: tx * TILE_WIDTH, y: ty * TILE_HEIGHT}
ptEquals = (p, q) -> p.x == q.x and p.y == q.y
ptAdd = (p, q) -> {x: p.x + q.x, y: p.y + q.y}
ptDiff = (p, q) -> {x: p.x - q.x, y: p.y - q.y}

class ShowThenHideSlider
  constructor: (@entity, @delta, @duration, @hideCb) ->
    @negativeDelta = {x: -@delta.x, y: -@delta.y}
    @startPos = {x: @entity.x, y: @entity.y}
    @targetPos = {x: @entity.x + @delta.x, y: @entity.y + @delta.y}
    @sliding = 'none'  # ['none', 'out', 'in']
    @slider = null

  tick: ->

  show: ->
    throw "." if @slider
    @slider = new PositionSlide @entity, @startPos, @targetPos, @duration
    @entity.addSubTicker @slider

  hide: ->
    @slider.alive = false  # ensure the slider doesn't tick any more
    @slider = @slider.inverse @hideCb
    @entity.addSubTicker @slider

class PositionSlide
  constructor: (@entity, from, to, @duration, @cb) ->
    @from = {x: from.x, y: from.y}
    @to = {x: to.x, y: to.y}
    @elapsed = 0
    @alive = true

  ticksLeft: ->
    r = @duration - @elapsed
    throw "huh" if r < 0
    r

  inverse: (cb) ->
    result = new PositionSlide @entity, @to, @from, @duration, cb
    result.elapsed = @ticksLeft()
    result

  tick: ->
    if @elapsed == @duration
      @cb?()
      @alive = false
      return
    @elapsed++
    @interpolatePosition()

  interpolatePosition: ->
    ratio = @elapsed / @duration
    dx = @to.x - @from.x
    dy = @to.y - @from.y
    @entity.x = @from.x + dx * ratio
    @entity.y = @from.y + dy * ratio

class GamePieceMenu extends Entity
  @width = 122
  @height = 43
  @id = 0
  SLIDE_DURATION = 6

  constructor: (x, @piece) ->
    super()
    @id = GamePieceMenu.id++
    @width = GamePieceMenu.width
    @height = GamePieceMenu.height
    @x = x
    @y = SCREEN_HEIGHT + 1  # start off the bottom of the screen
    @visible = false
    @zIndex = CURSOR
    @slider = new ShowThenHideSlider @, {x:0, y:-@height - 10}, SLIDE_DURATION, =>
      @kill()
    @slider.show()

  tick: ->

  hide: ->
    @slider.hide()

  drawBar: (ctx, filled, max, x, y, width, height) ->
    ctx.save()
    ctx.fillStyle = 'red'
    ctx.fillRect x, y, width, height
    ctx.fillStyle = 'green'
    ctx.fillRect x, y, (width * (filled / max)), height
    ctx.strokeStyle = 'black'
    ctx.strokeRect x - 0.5, y - 0.5, width, height
    ctx.restore()

  draw: (ctx) ->
    ctx.fillStyle = 'white'
    ctx.fillRect @x, @y, @width, @height
    ctx.fillStyle = 'black'
    ctx.font = '9px volter'
    x = @x + 4
    y = @y + 12
    ctx.fillText @piece.name + '  Lvl 16', x, y
    y += 11
    @drawBar ctx, @piece.stats.hp, @piece.stats.hpMax, x + 16, y - 7, 90, 7
    ctx.fillText 'HP', x, y
    y += 11
    @drawBar ctx, @piece.stats.mp, @piece.stats.mpMax, x + 16, y - 7, 90, 7
    ctx.fillText 'MP', x, y
    ctx.strokeStyle = 'black'
    ctx.strokeRect @x - 0.5, @y - 0.5, @width, @height

class GamePiece extends Entity
  constructor: (@name, @team, @tx, @ty, stats, @imgSet) ->
    @stats = cloneObject stats
    super()
    @selected = false
    @zIndex = PIECE
    @dir = 'down'
    @x = @tx * TILE_WIDTH
    @y = @ty * TILE_HEIGHT

  select: ->
    return if @selected
    @selected = true
    @menu = new GamePieceMenu 10, @

  deselect: ->
    @dir = 'down'
    @selected = false
    @radius = null
    @menu.hide()
    @menu = null

  tick: ->

  kill: ->
    @menu.kill()
    super()

  draw: (ctx) ->
    ctx.drawImage @imgSet[@dir], @x, @y
    if @selected
      ctx.strokeStyle = 'black'
      ctx.strokeRect @x, @y, @width, @height

  setDirection: (@dir) ->

  face: (piece) ->
    dir =
      if @tx < piece.tx then 'right'
      else if @tx > piece.tx then 'left'
      else if @ty < piece.ty then 'down'
      else if @ty > piece.ty then 'up'
    @setDirection dir

  moveBy: (delta, cb) ->
    dpx = {x: delta.x * TILE_WIDTH, y: delta.y * TILE_HEIGHT}
    posSlide = new PositionSlide @, @, ptAdd(@, dpx), WALK_TICKS, =>
      @tx += delta.x
      @ty += delta.y
      cb()
    @addSubTicker posSlide

  getEnemiesInRange: (pieces) ->
    p for p in pieces when p.team != @team and @manhattanDistTx(p) <= @stats.range

  manhattanDistTx: (p) ->
    Math.abs(@tx - p.tx) + Math.abs(@ty - p.ty)

signum = (x) ->
  if x < 0
    -1
  else if x == 0
    0
  else
    1

clamp = (x, max_mag) ->
  signum(x) * Math.min(Math.abs(x), max_mag)

class Cursor extends Entity
  constructor: (x, y) ->
    super()
    @x = x
    @y = y
    @zIndex = CURSOR

  draw: (ctx) ->
    ctx.strokeStyle = 'black'
    ctx.strokeRect @x, @y, TILE_WIDTH, TILE_HEIGHT

  isOverTargetPiece: ->
    return true unless @targetPiece
    return @targetPiece.x == @x and @targetPiece.y == @y

  isMoving: ->
    not @isOverTargetPiece()

  tick: ->
    unless @isOverTargetPiece()
      @moveOneStepCloserToPiece()
      if @isOverTargetPiece()
        @cb()

  moveOneStepCloserToPiece: ->
    dx = @x - @targetPiece.x
    dy = @y - @targetPiece.y
    dx = clamp dx, CURSOR_MOVE_PX
    dy = clamp dy, CURSOR_MOVE_PX
    @x -= dx
    @y -= dy

  slideOverPiece: (@targetPiece, @cb) ->
    if @isOverTargetPiece()
      @cb()

moveSearch = (tileMap, start, depth) ->
  output = tileMap.makeGrid -1
  output[start[1]][start[0]] = depth

  getBestCostFromNeighbor = (pt) ->
    candidates = []
    for [x, y] in tileMap.neighbors pt
      candidates.push output[y][x]
    max = -1
    for candidate in candidates
      max = Math.max candidate, max
    max

  q = []

  visit = (pt, d) ->
    [x, y] = pt
    return if d < 0
    output[y][x] = d
    for pt in tileMap.neighbors pt
      if (tileMap.inBounds pt[0], pt[1]) and (output[pt[1]][pt[0]] == -1)
        q.push pt

  visit start, depth
  until q.length == 0
    [pt] = q.splice 0, 1
    [x, y] = pt
    n = getBestCostFromNeighbor pt
    d = n - tileMap.costAt x, y
    visit pt, d
  output

class Radius extends Entity
  MAX_MAP_WIDTH = 1024
  constructor: (@tx, @ty, @movePoints, @tileMap) ->
    super()
    @zIndex = RADIUS
    costAt = (pt) => @tileMap.costAt pt[0], pt[1]
    neighborsFn = (pt) =>
      [pt[0] + dx, pt[1] + dy] for [dx, dy] in [[0, -1], [0, 1], [-1, 0], [1, 0]]
    @canMoveGrid = moveSearch @tileMap, [@tx, @ty], @movePoints

  draw: (ctx) ->
    ctx.fillStyle = 'rgba(30, 30, 30, 0.30)'
    for tx in [0...@tileMap.width]
      for ty in [0...@tileMap.height]
        if @canMoveGrid[ty][tx] >= 0
          @fillTileAt tx, ty

  canMove: (x, y) ->
    @tileMap.inBounds(x, y) and @canMoveGrid[y][x] >= 0

  distanceTo: (tx, ty) ->
    Math.abs(@tx - tx) + Math.abs(@ty - ty)

  fillTileAt: (tx, ty) ->
    ctx.fillRect tx * TILE_WIDTH, ty * TILE_HEIGHT, TILE_WIDTH, TILE_HEIGHT

# Move the cursor between targets.
class AttackSession
  constructor: (@piece, @enemies) ->
    @cursor = new Cursor @piece.x, @piece.y
    @zIndex = CURSOR
    @enemyI = 0
    @action = null  # will be 'attack' or 'cancel' when done.
    @slide()

  slide: ->
    @targetMenu.hide() if @targetMenu
    @piece.face @enemies[@enemyI]
    @targetMenu = new GamePieceMenu SCREEN_WIDTH - GamePieceMenu.width - 10, @enemies[@enemyI]
    @sliding = true
    @cursor.slideOverPiece @enemies[@enemyI], =>
      @sliding = false

  inputUpdated: (controller) ->
    return false if @sliding
    if controller.action()  # select the current target piece
      if @targetMenu
        @targetMenu.hide()
      @cursor.kill()
      @action = 'attack'
      return true
    if controller.left() or controller.up()
      @selectNext -1
    if controller.right() or controller.down()
      @selectNext +1
    if controller.cancel()
      @cursor.kill()
      @action = 'cancel'
      return true

  selectNext: (delta) ->
    nextEnemyI = (@enemyI + delta + @enemies.length) % @enemies.length
    return if nextEnemyI == @enemyI
    @enemyI = nextEnemyI
    @slide()

class PieceMoveSession
  constructor: (@piece, @radius, @pieces) ->
    @startTx = @piece.tx
    @startTy = @piece.ty
    @done = false
    @pieceMoving = false
    @menuDone = false

  inputUpdated: (controller) ->
    return true if @menuDone
    if controller.action()
      enemiesInRange = @piece.getEnemiesInRange @pieces
      defaultOption = if enemiesInRange.length > 0 then 'attack' else 'stay'
      moveConfirm = new OptionSelector ['attack', 'item', 'magic', 'stay'], defaultOption
      fs.push moveConfirm, =>
        return unless moveConfirm.committed
        switch moveConfirm.currentChoice
          when 'stay'
            @cleanUp()
          when 'attack'
            attackSession = new AttackSession @piece, enemiesInRange
            fs.push attackSession, =>
              if attackSession.action == 'cancel'
                return
              @cleanUp()
            return

    delta = controller.delta()
    return unless delta
    @piece.setDirection controller.dir()
    {x:dx, y:dy} = delta
    if @radius.canMove @piece.tx + dx, @piece.ty + dy
      @piece.moveBy delta, fs.block()
    false

  cleanUp: ->
    @radius.kill()
    @menuDone = true

class InputBlocker
  inputUpdated: (controller) -> false

isActionEvent = (event) ->
  switch event.keyCode
    when VKEY_ENTER then 'action'

eventToDir = (event) ->
  switch event.keyCode
    when VKEY_LEFT then {x:-1, y:0}
    when VKEY_UP then {x:0, y:-1}
    when VKEY_RIGHT then {x:1, y:0}
    when VKEY_DOWN then {x:0, y:1}

class TileMap
  GRASS = 0
  DIRT = 1

  constructor: (@width, @height, @imgSet) ->
    @tiles = (x, y) -> if x < 5 then DIRT else GRASS
    @costs = [1, 2]
    @names = ['grass', 'dirt']

  draw: (ctx) ->
    for x in [0...@width]
      for y in [0...@height]
        xPx = x * TILE_WIDTH
        yPx = y * TILE_HEIGHT
        ctx.drawImage @imgSet[@names[@tiles(x, y)]], xPx, yPx

  costAt: (x, y) ->
    t = @costs[@tiles x, y]
    if t then t else 100

  inBounds: (x, y) ->
    0 <= x < @width and 0 <= y < @height

  makeGrid: (val) ->
    output = []
    for y in [0...@height]
      row = []
      for x in [0...@width]
        row.push -1
      output.push row
    output

  neighbors: (pt) ->
    [x, y] = pt
    deltas = [[0, -1], [0, 1], [-1, 0], [1, 0]]
    for [dx, dy] in deltas when @inBounds x + dx, y + dy
      [x + dx, y + dy]

class Game
  PLAYER_STATS =
    hpMax: 30
    mpMax: 0
    hp: 30
    mp: 0
    attack: 3
    defense: 2
    range: 1

  ENEMY_STATS =
    hpMax: 12
    mpMax: 0
    hp: 12
    mp: 0
    attack: 2
    defense: 1
    range: 1

  constructor: (@tileMap) ->
    m = new GamePiece 'JAMES', PLAYER_TEAM, 1, 2, PLAYER_STATS, fighterImgs
    m1 = new GamePiece 'RED SKELETON', ENEMY_TEAM, 8, 2, ENEMY_STATS, enemyFighterImgs
    m2 = new GamePiece 'RED SKELETON', ENEMY_TEAM, 8, 4, ENEMY_STATS, enemyFighterImgs
    @pieces = [m, m1, m2]
    @selectedIndex = 0
    @selected = @pieces[@selectedIndex]
    @movePiece = null
    fs.push @
    @startTurn 0, 0, m

  inputUpdated: (controller) ->
    return false

  nextSelectedIndex: -> (@selectedIndex + 1) % @pieces.length

  selectNext: ->
    @selected.deselect()
    x = @selected.x
    y = @selected.y
    @selectedIndex = @nextSelectedIndex()
    @selected = @pieces[@selectedIndex]
    @startTurn x, y, @selected

  startTurn: (x, y, piece) ->
    @cursor = new Cursor x, y
    @cursor.slideOverPiece piece, =>
      piece.select()
      @cursor.kill()
      @cursor = null

      radius = new Radius piece.tx, piece.ty, MOVEMENT_RANGE, @tileMap
      movePiece = new PieceMoveSession piece, radius, @pieces
      fs.push movePiece, =>
        @selectNext()

class Controller
  VKEY_COMMAND = 91
  constructor: ->
    @keysDown = {}
    @ignoreAll = false

  handleKeyDown: (event) ->
    # on mac chrome, keys pressed while command is down don't emit keyup
    @ignoreAll = true if event.keyCode == VKEY_COMMAND
    return if @ignoreAll
    @keysDown[event.keyCode] = true

  handleKeyUp: (event) ->
    @ignoreAll = false if event.keyCode == VKEY_COMMAND
    return if @ignoreAll
    @keysDown[event.keyCode] = false

  action: -> @keysDown[VKEY_ENTER]
  cancel: -> @keysDown[VKEY_SEMICOLON]

  up: -> @dir() == 'up'
  down: -> @dir() == 'down'
  left: -> @dir() == 'left'
  right: -> @dir() == 'right'
  dir: ->
    return 'left' if @keysDown[VKEY_LEFT] or @keysDown[VKEY_H]
    return 'right' if @keysDown[VKEY_RIGHT] or @keysDown[VKEY_L]
    return 'up' if @keysDown[VKEY_UP] or @keysDown[VKEY_K]
    return 'down' if @keysDown[VKEY_DOWN] or @keysDown[VKEY_J]
  delta: ->
    switch @dir()
      when 'left' then {x:-1, y:0}
      when 'right' then {x:1, y:0}
      when 'up' then {x:0, y:-1}
      when 'down' then {x:0, y:1}

tm = new TileMap 20, 20, tileImgs
c = new Controller
g = new Game tm

document.addEventListener 'keydown', (e) ->
  c.handleKeyDown e
, false

document.addEventListener 'keyup', (e) ->
  c.handleKeyUp e
, false

gameLoop = ->
  clear()
  es.tick()
  fs.inputUpdated c
  tm.draw ctx
  e.draw ctx for e in es.entities when e.zIndex == RADIUS
  e.draw ctx for e in es.entities when e.zIndex == PIECE
  e.draw ctx for e in es.entities when e.zIndex == CURSOR

id = setInterval gameLoop, (1000/FPS)

stop = -> clearInterval id
