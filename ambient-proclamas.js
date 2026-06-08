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
    const FALLBACK_MESSAGES = [
      'Cepeda Presidente 2026',
      'Paz con garantía territorial',
      'Colombia potencia de la vida',
      'Soberanía popular para el pueblo',
      'Justicia social en cada región',
      'Unidad por Colombia',
      'Reforma agraria ya',
      'Pacto histórico por la vida'
    ];

    function clamp(value, min, max) {
      return Math.max(min, Math.min(max, value));
    }

    function dedupe(items) {
      return Array.from(new Set(items.filter(Boolean)));
    }

    function normalizeMessage(message) {
      return String(message || '')
        .replace(/\s+/g, ' ')
        .replace(/^["'“”]+|["'“”]+$/g, '')
        .trim()
        .slice(0, 88);
    }

    function getItemBottom(item) {
      const hasExplicitHeight = item && typeof item.height === 'number';
      const height = hasExplicitHeight ? Math.max(0, item.height) : 42;
      const y = item && typeof item.y === 'number' ? item.y : 0;
      return y + height;
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
          return getItemBottom(item) > spawnY - minVerticalGap;
        });

        if (blocked) {
          continue;
        }

        const nearestBottom = laneItems.length
          ? Math.max.apply(
              null,
              laneItems.map(function(item) {
                return getItemBottom(item);
              })
            )
          : -Infinity;

        candidates.push({
          laneIndex: lane.index,
          x: lane.x,
          activeCount: laneItems.length,
          nearestBottom
        });
      }

      if (!candidates.length) {
        return null;
      }

      candidates.sort(function(a, b) {
        if (a.activeCount !== b.activeCount) {
          return a.activeCount - b.activeCount;
        }
        return a.nearestBottom - b.nearestBottom;
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
          bubbleWidth: 232,
          bubbleMinWidth: 180,
          gutter: 24,
          sidePadding: 18,
          spawnIntervalMs: 1150,
          minVerticalGap: 150,
          maxActiveItems: 8,
          speedPxPerSecond: 34
        },
        options || {}
      );

      const state = {
        activeItems: [],
        pool: [],
        lastSpawnAt: 0,
        lastFrameAt: 0,
        frameId: 0,
        poolRefreshId: 0,
        running: false,
        lanes: []
      };

      function getLayer() {
        return root.document.getElementById(settings.layerId);
      }

      function refreshLanes() {
        const maxWidth = root.innerWidth <= 640 ? settings.bubbleMinWidth : settings.bubbleWidth;
        state.lanes = computeLanes({
          viewportWidth: root.innerWidth,
          bubbleWidth: maxWidth,
          gutter: settings.gutter,
          sidePadding: settings.sidePadding
        });
      }

      function extractMessagesFromCards() {
        const cards = Array.from(root.document.querySelectorAll('#wallCards > *'));
        return cards
          .map(function(card) {
            const lines = card.innerText
              .split('\n')
              .map(function(line) {
                return line.trim();
              })
              .filter(Boolean);
            if (!lines.length) {
              return '';
            }
            const title = lines[0];
            const quote = lines.find(function(line) {
              return /["“”]/.test(line) || line.length > 18;
            });
            const badge = lines.find(function(line) {
              return line !== title && line !== quote && line.length < 24;
            });
            const composed = badge && quote ? badge + ' · ' + quote : quote || title;
            return normalizeMessage(composed);
          })
          .filter(Boolean);
      }

      function extractMessagesFromTabs() {
        return Array.from(root.document.querySelectorAll('#tabMuroBtn, #tabLeaderBtn, #tabTappersBtn'))
          .map(function(node) {
            return normalizeMessage(node.textContent);
          })
          .filter(Boolean);
      }

      function refreshPool() {
        state.pool = dedupe(
          extractMessagesFromCards()
            .concat(extractMessagesFromTabs())
            .concat(FALLBACK_MESSAGES)
        );
      }

      function createBubble(message, laneChoice) {
        const layer = getLayer();
        if (!layer) {
          return null;
        }

        const bubble = root.document.createElement('div');
        bubble.className = 'ambient-proclama';
        bubble.textContent = normalizeMessage(message);
        bubble.style.maxWidth = root.innerWidth <= 640 ? '74vw' : '260px';
        bubble.style.left = laneChoice.x + 'px';
        bubble.style.top = '0px';
        bubble.style.transform = 'translate(-50%, 0px)';
        layer.appendChild(bubble);

        const rect = bubble.getBoundingClientRect();
        return {
          node: bubble,
          laneIndex: laneChoice.laneIndex,
          x: laneChoice.x,
          y: root.innerHeight + 16,
          width: rect.width || settings.bubbleWidth,
          height: rect.height || 42,
          speed: settings.speedPxPerSecond
        };
      }

      function removeItem(item) {
        if (item.node && item.node.parentNode) {
          item.node.parentNode.removeChild(item.node);
        }
      }

      function spawn(now) {
        if (now - state.lastSpawnAt < settings.spawnIntervalMs) {
          return;
        }
        if (state.activeItems.length >= settings.maxActiveItems) {
          return;
        }
        if (!state.pool.length) {
          refreshPool();
        }
        if (!state.pool.length) {
          return;
        }

        refreshLanes();
        const laneChoice = pickSpawnLane({
          lanes: state.lanes,
          activeItems: state.activeItems,
          spawnY: root.innerHeight + 16,
          minVerticalGap: settings.minVerticalGap
        });

        if (!laneChoice) {
          return;
        }

        const message = state.pool[Math.floor(Math.random() * state.pool.length)];
        const item = createBubble(message, laneChoice);
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

        const delta = state.lastFrameAt ? (now - state.lastFrameAt) / 1000 : 0.016;
        state.lastFrameAt = now;

        spawn(now);

        state.activeItems = state.activeItems.filter(function(item) {
          item.y -= item.speed * delta;
          if (item.node) {
            item.node.style.transform = 'translate(-50%, ' + item.y.toFixed(2) + 'px)';
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
          return;
        }
        const layer = getLayer();
        if (!layer) {
          return;
        }
        root.document.documentElement.setAttribute('data-ambient-proclamas', 'on');
        refreshPool();
        refreshLanes();
        state.running = true;
        state.lastFrameAt = 0;
        state.lastSpawnAt = 0;
        state.frameId = root.requestAnimationFrame(tick);
        state.poolRefreshId = root.setInterval(refreshPool, 5000);
      }

      function stop() {
        state.running = false;
        if (state.frameId) {
          root.cancelAnimationFrame(state.frameId);
          state.frameId = 0;
        }
        if (state.poolRefreshId) {
          root.clearInterval(state.poolRefreshId);
          state.poolRefreshId = 0;
        }
        state.activeItems.forEach(removeItem);
        state.activeItems = [];
      }

      return {
        start,
        stop,
        refreshPool,
        refreshLanes
      };
    }

    function autoStart() {
      if (!root || !root.document) {
        return;
      }
      root.document.addEventListener('DOMContentLoaded', function() {
        if (root.matchMedia && root.matchMedia('(prefers-reduced-motion: reduce)').matches) {
          root.document.documentElement.removeAttribute('data-ambient-proclamas');
          return;
        }
        const controller = createAmbientProclamasController();
        controller.start();
        root.addEventListener('resize', controller.refreshLanes);
        root.document.addEventListener('visibilitychange', function() {
          if (root.document.hidden) {
            controller.stop();
            return;
          }
          controller.start();
        });
      });
    }

    autoStart();

    return {
      FALLBACK_MESSAGES,
      computeLanes,
      pickSpawnLane,
      createAmbientProclamasController
    };
  }
);
