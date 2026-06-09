(function (root, factory) {
  var api = factory(root);
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
  if (root) {
    root.AmbientProclamas = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function (root) {
  function normalizeMessage(message) {
    return String(message || "")
      .replace(/\s+/g, " ")
      .replace(/^["'""]+|["'""]+$/g, "")
      .trim()
      .slice(0, 150);
  }

  function parseProclamaMessage(message) {
    var text = normalizeMessage(message);
    if (!text) return { city: "", msg: text };
    var sepIdx = text.indexOf(" \u00b7 ");
    if (sepIdx > 0) {
      return {
        city: text.slice(0, sepIdx).trim(),
        msg: text.slice(sepIdx + 3).trim(),
      };
    }
    return { city: "", msg: text };
  }

  function createCLogoSVG() {
    return (
      '<svg class="proclama-card__c-icon" viewBox="0 0 34 34" fill="none" xmlns="http://www.w3.org/2000/svg">' +
      '<defs><linearGradient id="cg" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#FCD116"/><stop offset="100%" stop-color="#C59B27"/></linearGradient></defs>' +
      '<path d="M19 8 C14 8 9 11 8 17 C7 22 10 26 15 26 C17 26 19 25 21 23" stroke="url(#cg)" stroke-width="2.2" stroke-linecap="round" fill="none"/>' +
      '<path d="M16 15 C17 13 19 12 20 13 C21 14 20 16 18 15" stroke="url(#cg)" stroke-width="1.5" stroke-linecap="round" fill="none" opacity="0.9"/>' +
      '<path d="M14 19 C14 17 15 16 16 17 C16 18 15 19 14 19Z" stroke="url(#cg)" stroke-width="1.2" stroke-linecap="round" fill="none" opacity="0.7"/>' +
      '<circle cx="22" cy="7" r="1.2" fill="#F3D26C" opacity="0.8"/>' +
      "</svg>"
    );
  }

  function resolveBubbleWidth(viewportWidth, settings) {
    if (viewportWidth <= 520) {
      return Math.max(
        164,
        Math.min(settings.mobileBubbleWidth || 188, viewportWidth - 28),
      );
    }
    if (viewportWidth <= 960) {
      return Math.max(188, settings.tabletBubbleWidth || 236);
    }
    return Math.max(240, settings.bubbleWidth || 296);
  }

  function computeLanes(config) {
    var viewportWidth = Math.max(320, config.viewportWidth || 0);
    var bubbleWidth = Math.max(160, config.bubbleWidth || 220);
    var gutter = Math.max(8, config.gutter || 24);
    var sidePadding = Math.max(0, config.sidePadding || 24);
    var usableWidth = Math.max(bubbleWidth, viewportWidth - sidePadding * 2);
    var estimatedCount = Math.max(
      1,
      Math.floor((usableWidth + gutter) / (bubbleWidth + gutter)),
    );
    var firstCenter = sidePadding + bubbleWidth / 2;
    var lastCenter = viewportWidth - sidePadding - bubbleWidth / 2;

    if (estimatedCount === 1 || lastCenter <= firstCenter) {
      return [{ index: 0, x: viewportWidth / 2 }];
    }

    var span = lastCenter - firstCenter;
    return Array.from({ length: estimatedCount }, function (_, index) {
      return {
        index: index,
        x: firstCenter + (span * index) / (estimatedCount - 1),
      };
    });
  }

  function pickSpawnLane(config) {
    var lanes = Array.isArray(config.lanes) ? config.lanes : [];
    var activeItems = Array.isArray(config.activeItems)
      ? config.activeItems
      : [];
    var spawnY = config.spawnY || 0;
    var minVerticalGap = Math.max(80, config.minVerticalGap || 140);
    var candidates = [];

    for (var i = 0; i < lanes.length; i++) {
      var lane = lanes[i];
      var laneItems = activeItems.filter(function (item) {
        return item.laneIndex === lane.index;
      });
      var blocked = laneItems.some(function (item) {
        var itemTop = item && typeof item.y === "number" ? item.y : 0;
        return itemTop > spawnY - minVerticalGap;
      });

      if (blocked) {
        continue;
      }

      var nearestTop = laneItems.length
        ? Math.max.apply(
            null,
            laneItems.map(function (item) {
              return item && typeof item.y === "number" ? item.y : 0;
            }),
          )
        : -Infinity;

      candidates.push({
        laneIndex: lane.index,
        x: lane.x,
        activeCount: laneItems.length,
        nearestTop: nearestTop,
      });
    }

    if (!candidates.length) {
      return null;
    }

    candidates.sort(function (a, b) {
      if (a.activeCount !== b.activeCount) {
        return a.activeCount - b.activeCount;
      }
      return a.nearestTop - b.nearestTop;
    });

    return {
      laneIndex: candidates[0].laneIndex,
      x: candidates[0].x,
    };
  }

  function createAmbientProclamasController(options) {
    var settings = Object.assign(
      {
        layerId: "ambientProclamasLayer",
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
        maxQueueItems: 30,
      },
      options || {},
    );

    var state = {
      activeItems: [],
      queue: [],
      running: false,
      frameId: 0,
      lastFrameAt: 0,
      lastSpawnAt: 0,
      lanes: [],
      spawnCount: 0,
      featuredSpawned: false,
    };

    function getLayer() {
      return root.document.getElementById(settings.layerId);
    }

    function refreshLanes() {
      var maxWidth = resolveBubbleWidth(root.innerWidth, settings);
      state.lanes = computeLanes({
        viewportWidth: root.innerWidth,
        bubbleWidth: maxWidth,
        gutter: settings.gutter,
        sidePadding: settings.sidePadding,
      });
    }

    function createCard(message, laneChoice, isFeatured, accentColor) {
      var layer = getLayer();
      if (!layer) {
        return null;
      }

      var parsed = parseProclamaMessage(message);
      var cardWidth = Math.max(
        260,
        Math.min(390, resolveBubbleWidth(root.innerWidth, settings) + 40),
      );
      var spawnY = root.innerHeight + settings.spawnLeadPx;

      var accentClass = accentColor ? " proclama-card--accent-" + accentColor : "";
      var card = root.document.createElement("div");
      card.className = isFeatured
        ? "proclama-card proclama-card--featured" + accentClass
        : "proclama-card" + accentClass;
      card.style.width = cardWidth + "px";
      card.style.maxWidth = cardWidth + "px";
      card.style.left = laneChoice.x + "px";
      card.style.top = "0px";
      card.style.transform = "translate(-50%, 0px)";

      // TU PROCLAMA badge on featured cards
      if (isFeatured) {
        var badge = root.document.createElement("div");
        badge.className = "proclama-card__badge";
        badge.textContent = "TU PROCLAMA";
        card.appendChild(badge);
      }

      // C + Rose logo
      var logoWrap = root.document.createElement("div");
      logoWrap.className = "proclama-card__logo";
      logoWrap.innerHTML = createCLogoSVG();

      // Content: city + message
      var content = root.document.createElement("div");
      content.className = "proclama-card__content";

      if (parsed.city) {
        var cityEl = root.document.createElement("span");
        cityEl.className = "proclama-card__city";
        cityEl.textContent = parsed.city;
        content.appendChild(cityEl);
      }

      var msgEl = root.document.createElement("span");
      msgEl.className = "proclama-card__message";
      msgEl.textContent = parsed.msg;
      content.appendChild(msgEl);

      card.appendChild(logoWrap);
      card.appendChild(content);
      layer.appendChild(card);

      var rect = card.getBoundingClientRect();
      var halfWidth = (rect.width || cardWidth) / 2;
      var clampedX = Math.min(
        root.innerWidth - halfWidth - settings.sidePadding,
        Math.max(halfWidth + settings.sidePadding, laneChoice.x),
      );
      card.style.left = clampedX + "px";
      return {
        node: card,
        laneIndex: laneChoice.laneIndex,
        x: clampedX,
        y: spawnY,
        width: rect.width || cardWidth,
        height: rect.height || 64,
        speed: settings.speedPxPerSecond,
        isFeatured: !!isFeatured,
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
      var spawnY = root.innerHeight + settings.spawnLeadPx;
      var laneChoice = pickSpawnLane({
        lanes: state.lanes,
        activeItems: state.activeItems,
        spawnY: spawnY,
        minVerticalGap: settings.minVerticalGap,
      });

      if (!laneChoice) {
        return;
      }

      var nextMessage = state.queue.shift();
      state.spawnCount++;

      var accentColors = ["gold", "blue", "red"];
      var accentColor = state.featuredSpawned
        ? accentColors[state.spawnCount % 3]
        : accentColors[(state.spawnCount + 1) % 3];

      // Every ~8th card is the featured "TU PROCLAMA" card, but only once per session
      var isFeatured =
        !state.featuredSpawned &&
        state.spawnCount > 0 &&
        state.spawnCount % 8 === 0;
      if (isFeatured) {
        state.featuredSpawned = true;
      }

      var item = createCard(nextMessage, laneChoice, isFeatured, accentColor);
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

      var delta = Math.min(0.05, (now - state.lastFrameAt) / 1000);
      state.lastFrameAt = now;

      trySpawn(now);

      state.activeItems = state.activeItems.filter(function (item) {
        item.y -= item.speed * delta;
        if (item.node) {
          item.node.style.transform =
            "translate3d(-50%, " + item.y.toFixed(2) + "px, 0)";
        }
        var offscreen = item.y < -(item.height + 80);
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
      var layer = getLayer();
      if (!layer) {
        return false;
      }
      refreshLanes();
      root.document.documentElement.setAttribute(
        "data-ambient-proclamas",
        "on",
      );
      state.running = true;
      state.lastFrameAt = 0;
      state.lastSpawnAt = 0;
      state.spawnCount = 0;
      state.featuredSpawned = false;
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
        root.document.documentElement.removeAttribute("data-ambient-proclamas");
      }
    }

    function enqueue(message) {
      var normalized = normalizeMessage(message);
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
      start: start,
      stop: stop,
      enqueue: enqueue,
      isRunning: isRunning,
      refreshLanes: refreshLanes,
    };
  }

  return {
    computeLanes: computeLanes,
    pickSpawnLane: pickSpawnLane,
    createAmbientProclamasController: createAmbientProclamasController,
  };
});
