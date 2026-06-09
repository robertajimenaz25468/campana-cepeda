(function(root, factory) {
  const api = factory(root);
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  }
  if (root) {
    root.AmbientProclamas = api;
  }
})(
  typeof globalThis !== 'undefined' ? globalThis : this,
  function(root) {
    function normalizeMessage(message) {
      return String(message || '')
        .replace(/\s+/g, ' ')
        .replace(/^["'“”]+|["'“”]+$/g, '')
        .trim()
        .slice(0, 88);
    }

    function resolveBubbleWidth(viewportWidth, settings) {
      if (viewportWidth <= 520) {
        return Math.max(164, Math.min(settings.mobileBubbleWidth || 188, viewportWidth - 28));
      }
      if (viewportWidth <= 960) {
        return Math.max(188, settings.tabletBubbleWidth || 236);
      }
      return Math.max(240, settings.bubbleWidth || 296);
    }

    function computeLanes(config) {
      const viewportWidth = Math.max(320, config.viewportWidth || 0);
      const bubbleWidth = Math.max(160, config.bubbleWidth || 220);
      const gutter = Math.max(8, config.gutter || 24);
      const sidePadding = Math.max(0, config.sidePadding || 24);
      const usableWidth = Math.max(bubbleWidth, viewportWidth - sidePadding * 2);
      const estimatedCount = Math.max(1, Math.floor((usableWidth + gutter) / (bubbleWidth + gutter)));
      const firstCenter = sidePadding + bubbleWidth / 2;
      const lastCenter = viewportWidth - sidePadding - bubbleWidth / 2;

      if (estimatedCount === 1 || lastCenter <= firstCenter) {
        return [{ index: 0, x: viewportWidth / 2 }];
      }

      const span = lastCenter - firstCenter;
      return Array.from({ length: estimatedCount }, function(_, index) {
        return {
          index,
          x: firstCenter + (span * index) / (estimatedCount - 1)
        };
      });
    }

    function pickSpawnLane(config) {
      const lanes = Array.isArray(config.lanes) ? config.lanes : [];
      const activeItems = Array.isArray(config.activeItems) ? config.activeItems : [];
      const spawnY = config.spawnY || 0;
      const minVerticalGap = Math.max(80, config.minVerticalGap || 140);
      const candidates = [];

      for (const lane of lanes) {
        const laneItems = activeItems.filter(function(item) {
          return item.laneIndex === lane.index;
        });
        const blocked = laneItems.some(function(item) {
          const itemTop = item && typeof item.y === 'number' ? item.y : 0;
          return itemTop > spawnY - minVerticalGap;
        });

        if (blocked) {
          continue;
        }

        const nearestTop = laneItems.length
          ? Math.max.apply(
              null,
              laneItems.map(function(item) {
                return item && typeof item.y === 'number' ? item.y : 0;
              })
            )
          : -Infinity;

        candidates.push({
          laneIndex: lane.index,
          x: lane.x,
          activeCount: laneItems.length,
          nearestTop
        });
      }

      if (!candidates.length) {
        return null;
      }

      candidates.sort(function(a, b) {
        if (a.activeCount !== b.activeCount) {
          return a.activeCount - b.activeCount;
        }
        return a.nearestTop - b.nearestTop;
      });

      return {
        laneIndex: candidates[0].laneIndex,
        x: candidates[0].x
      };
    }

    function createAmbientProclamasController(options) {
      const settings = Object.assign(
        {
          layerId: 'ambientProclamasLayer',
          bubbleWidth: 296,
          tabletBubbleWidth: 236,
          mobileBubbleWidth: 188,
          gutter: 18,
          sidePadding: 18,
          spawnLeadPx: 66,
          spawnIntervalMs: 70,
          minVerticalGap: 52,
          maxActiveItems: 14,
          speedPxPerSecond: 56,
          maxQueueItems: 30
        },
        options || {}
      );

      const state = {
        activeItems: [],
        queue: [],
        running: false,
        frameId: 0,
        lastFrameAt: 0,
        lastSpawnAt: 0,
        lanes: []
      };

      function getLayer() {
        return root.document.getElementById(settings.layerId);
      }

      function refreshLanes() {
        const maxWidth = resolveBubbleWidth(root.innerWidth, settings);
        state.lanes = computeLanes({
          viewportWidth: root.innerWidth,
          bubbleWidth: maxWidth,
          gutter: settings.gutter,
          sidePadding: settings.sidePadding
        });
      }

      function createBubble(message, laneChoice) {
        const layer = getLayer();
        if (!layer) {
          return null;
        }

        const bubbleWidth = resolveBubbleWidth(root.innerWidth, settings);
        const spawnY = root.innerHeight + settings.spawnLeadPx;
        const bubble = root.document.createElement('div');
        bubble.className = 'ambient-proclama';
        bubble.style.width = bubbleWidth + 'px';
        bubble.style.maxWidth = bubbleWidth + 'px';
        bubble.style.minWidth = bubbleWidth + 'px';
        bubble.style.left = laneChoice.x + 'px';
        bubble.style.top = '0px';
        bubble.style.transform = 'translate(-50%, 0px)';

        const spark = root.document.createElement('span');
        spark.className = 'ambient-proclama__spark';

        const copy = root.document.createElement('span');
        copy.className = 'ambient-proclama__copy';
        copy.textContent = normalizeMessage(message);

        bubble.appendChild(spark);
        bubble.appendChild(copy);
        layer.appendChild(bubble);

        const rect = bubble.getBoundingClientRect();
        const halfWidth = (rect.width || bubbleWidth) / 2;
        const clampedX = Math.min(
          root.innerWidth - halfWidth - settings.sidePadding,
          Math.max(halfWidth + settings.sidePadding, laneChoice.x)
        );
        bubble.style.left = clampedX + 'px';
        return {
          node: bubble,
          laneIndex: laneChoice.laneIndex,
          x: clampedX,
          y: spawnY,
          width: rect.width || bubbleWidth,
          height: rect.height || 52,
          speed: settings.speedPxPerSecond
        };
      }

      function removeItem(item) {
        if (item.node && item.node.parentNode) {
          item.node.parentNode.removeChild(item.node);
        }
      }

      function trySpawn(now) {
        if (!state.running || !state.queue.length) {
          return;
        }
        if (state.activeItems.length >= settings.maxActiveItems) {
          return;
        }
        if (now - state.lastSpawnAt < settings.spawnIntervalMs) {
          return;
        }

        refreshLanes();
        const spawnY = root.innerHeight + settings.spawnLeadPx;
        const laneChoice = pickSpawnLane({
          lanes: state.lanes,
          activeItems: state.activeItems,
          spawnY,
          minVerticalGap: settings.minVerticalGap
        });

        if (!laneChoice) {
          return;
        }

        const nextMessage = state.queue.shift();
        const item = createBubble(nextMessage, laneChoice);
        if (!item) {
          return;
        }

        state.activeItems.push(item);
        state.lastSpawnAt = now;
      }

      function tick(now) {
        if (!state.running) {
          return;
        }

        if (!state.lastFrameAt) {
          state.lastFrameAt = now;
        }

        const delta = Math.min(0.05, (now - state.lastFrameAt) / 1000);
        state.lastFrameAt = now;

        trySpawn(now);

        state.activeItems = state.activeItems.filter(function(item) {
          item.y -= item.speed * delta;
          if (item.node) {
            item.node.style.transform = 'translate3d(-50%, ' + item.y.toFixed(2) + 'px, 0)';
          }
          const offscreen = item.y < -(item.height + 80);
          if (offscreen) {
            removeItem(item);
            return false;
          }
          return true;
        });

        state.frameId = root.requestAnimationFrame(tick);
      }

      function start() {
        if (!root.document || state.running) {
          return false;
        }
        const layer = getLayer();
        if (!layer) {
          return false;
        }
        refreshLanes();
        root.document.documentElement.setAttribute('data-ambient-proclamas', 'on');
        state.running = true;
        state.lastFrameAt = 0;
        state.lastSpawnAt = 0;
        state.frameId = root.requestAnimationFrame(tick);
        return true;
      }

      function stop() {
        state.running = false;
        state.queue = [];
        if (state.frameId) {
          root.cancelAnimationFrame(state.frameId);
          state.frameId = 0;
        }
        state.activeItems.forEach(removeItem);
        state.activeItems = [];
        if (root.document && root.document.documentElement) {
          root.document.documentElement.removeAttribute('data-ambient-proclamas');
        }
      }

      function enqueue(message) {
        const normalized = normalizeMessage(message);
        if (!state.running || !normalized) {
          return false;
        }
        state.queue.push(normalized);
        if (state.queue.length > settings.maxQueueItems) {
          state.queue = state.queue.slice(-settings.maxQueueItems);
        }
        return true;
      }

      function isRunning() {
        return state.running;
      }

      return {
        start,
        stop,
        enqueue,
        isRunning,
        refreshLanes
      };
    }

    return {
      computeLanes,
      pickSpawnLane,
      createAmbientProclamasController
    };
  }
);
