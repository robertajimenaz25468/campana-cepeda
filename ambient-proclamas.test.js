const test = require('node:test');
const assert = require('node:assert/strict');

const {
  computeLanes,
  pickSpawnLane
} = require('./ambient-proclamas.js');

test('computeLanes keeps lane centers inside viewport', () => {
  const lanes = computeLanes({
    viewportWidth: 1280,
    bubbleWidth: 220,
    gutter: 24,
    sidePadding: 24
  });

  assert.ok(lanes.length >= 3);
  assert.ok(lanes.every((lane) => lane.x >= 24 + 110));
  assert.ok(lanes.every((lane) => lane.x <= 1280 - 24 - 110));
});

test('pickSpawnLane skips blocked lanes and chooses a clear one', () => {
  const lanes = computeLanes({
    viewportWidth: 920,
    bubbleWidth: 220,
    gutter: 18,
    sidePadding: 20
  });

  const choice = pickSpawnLane({
    lanes,
    activeItems: [
      { laneIndex: 0, y: 760 },
      { laneIndex: 1, y: 610 }
    ],
    spawnY: 840,
    minVerticalGap: 120
  });

  assert.equal(choice.laneIndex, 2);
  assert.equal(choice.x, lanes[2].x);
});

test('pickSpawnLane returns null when all lanes are blocked near spawn edge', () => {
  const lanes = computeLanes({
    viewportWidth: 760,
    bubbleWidth: 210,
    gutter: 18,
    sidePadding: 18
  });

  const choice = pickSpawnLane({
    lanes,
    activeItems: lanes.map((lane, laneIndex) => ({
      laneIndex,
      y: 760 - laneIndex * 10
    })),
    spawnY: 820,
    minVerticalGap: 110
  });

  assert.equal(choice, null);
});

test('pickSpawnLane treats bubble height as part of the blocking gap', () => {
  const lanes = computeLanes({
    viewportWidth: 500,
    bubbleWidth: 210,
    gutter: 18,
    sidePadding: 18
  });

  const choice = pickSpawnLane({
    lanes,
    activeItems: [
      { laneIndex: 0, y: 650, height: 80 },
      { laneIndex: 1, y: 690, height: 5 }
    ],
    spawnY: 820,
    minVerticalGap: 120
  });

  assert.equal(choice.laneIndex, 1);
  assert.equal(choice.x, lanes[1].x);
});
