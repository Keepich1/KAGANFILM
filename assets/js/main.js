/* KAGANFILM: поведение страницы. Без зависимостей и без обработчиков scroll. */
(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

  // Одна сломанная часть не должна гасить остальные
  const safe = (fn, ...args) => {
    try { return fn(...args); } catch (err) { console.error(err); return undefined; }
  };

  const hero = $("[data-hero]");
  const lightOn = () => hero && hero.classList.add("is-lit");

  /* ---------- Языки: русский и кыргызский ----------
     Русский текст живёт в разметке, кыргызский в assets/js/i18n.js.
     Элементы помечены data-i18n (текст), data-i18n-html (текст с разметкой)
     и data-i18n-attr="атрибут:ключ; атрибут:ключ". */
  const DICT = window.KF_I18N || {};
  DICT.ru = DICT.ru || {};
  DICT.ky = DICT.ky || {};
  const LANGS = ["ru", "ky"];
  let lang = LANGS.includes(document.documentElement.lang) ? document.documentElement.lang : "ru";

  const t = (key, vars) => {
    let s = DICT[lang][key] ?? DICT.ru[key] ?? key;
    if (vars) s = s.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? vars[k] : m));
    return s;
  };
  const mailLink = (mail) => `<a href="mailto:${mail}">${mail}</a>`;
  const attrPairs = (el) => el.dataset.i18nAttr
    .split(";")
    .map((pair) => pair.split(":").map((x) => x.trim()))
    .filter(([a, k]) => a && k);

  // Русский текст берём из самой страницы, чтобы не хранить его дважды
  function captureRu() {
    $$("[data-i18n]").forEach((el) => { DICT.ru[el.dataset.i18n] ??= el.textContent.trim(); });
    $$("[data-i18n-html]").forEach((el) => { DICT.ru[el.dataset.i18nHtml] ??= el.innerHTML.trim(); });
    $$("[data-i18n-attr]").forEach((el) => attrPairs(el).forEach(([a, k]) => {
      DICT.ru[k] ??= el.getAttribute(a) || "";
    }));
  }

  function applyLang(next) {
    lang = LANGS.includes(next) ? next : "ru";
    const root = document.documentElement;
    root.lang = lang;
    const pick = (k) => DICT[lang][k] ?? DICT.ru[k];
    $$("[data-i18n]").forEach((el) => {
      const v = pick(el.dataset.i18n);
      if (v != null && el.textContent !== v) el.textContent = v;
    });
    $$("[data-i18n-html]").forEach((el) => {
      const v = pick(el.dataset.i18nHtml);
      if (v != null) el.innerHTML = v;
    });
    $$("[data-i18n-attr]").forEach((el) => attrPairs(el).forEach(([a, k]) => {
      const v = pick(k);
      if (v != null) el.setAttribute(a, v);
    }));
    $$("[data-lang]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === lang)));
    root.classList.remove("i18n-wait");
    document.dispatchEvent(new CustomEvent("kf:lang", { detail: lang }));
  }

  const onLang = (fn) => document.addEventListener("kf:lang", fn);

  function initLang() {
    captureRu();
    if (lang !== "ru") applyLang(lang);
    $$("[data-lang]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.lang === lang)));
    document.documentElement.classList.remove("i18n-wait");

    $$("[data-lang]").forEach((btn) => btn.addEventListener("click", () => {
      if (btn.dataset.lang === lang) return;
      applyLang(btn.dataset.lang);
      try { localStorage.setItem("kf-lang", lang); } catch (err) { /* приватный режим */ }
      try {
        const url = new URL(window.location.href);
        if (lang === "ru") url.searchParams.delete("lang");
        else url.searchParams.set("lang", lang);
        window.history.replaceState(null, "", url);
      } catch (err) { /* песочница без history */ }
    }));
  }

  /* ---------- Сцены, привязанные к прокрутке ----------
     Один цикл rAF читает положение блоков, пока хотя бы один из них
     на экране. Как только все ушли из кадра, цикл останавливается. */
  const scenes = [];
  let sceneRaf = 0;

  const sceneTick = () => {
    const vh = window.innerHeight;
    const active = scenes.filter((s) => s.visible);
    const rects = active.map((s) => s.el.getBoundingClientRect());
    active.forEach((s, i) => {
      const r = rects[i];
      if (r.top === s.lastTop && r.height === s.lastH && vh === s.lastVh) return;
      s.lastTop = r.top;
      s.lastH = r.height;
      s.lastVh = vh;
      s.update(r, vh);
    });
    sceneRaf = active.length ? requestAnimationFrame(sceneTick) : 0;
  };
  const kickScenes = () => {
    if (!sceneRaf) sceneRaf = requestAnimationFrame(sceneTick);
  };
  const sceneIO = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        const s = scenes.find((x) => x.el === e.target);
        if (s) s.visible = e.isIntersecting;
      });
      kickScenes();
    }, { rootMargin: "25% 0px" })
    : null;

  const addScene = (el, update) => {
    const s = { el, update, visible: true, lastTop: NaN, lastH: NaN, lastVh: NaN };
    scenes.push(s);
    if (sceneIO) sceneIO.observe(el);
    kickScenes();
    return () => { s.lastTop = NaN; kickScenes(); };
  };

  /* ---------- Навигация ---------- */
  function initNav() {
    const nav = $("[data-nav]");
    if (!nav || !("IntersectionObserver" in window)) return;
    const sentinel = document.createElement("div");
    sentinel.setAttribute("aria-hidden", "true");
    sentinel.style.cssText = "position:absolute;top:0;left:0;width:1px;height:64px;pointer-events:none;";
    document.body.prepend(sentinel);
    new IntersectionObserver(([entry]) => {
      nav.classList.toggle("is-solid", !entry.isIntersecting);
    }).observe(sentinel);
  }

  /* ---------- Мобильное меню ---------- */
  function initMenu() {
    const toggle = $("[data-menu-toggle]");
    const menu = $("[data-menu]");
    if (!toggle || !menu) return;

    const setOpen = (open) => {
      menu.hidden = !open;
      document.body.classList.toggle("menu-open", open);
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", t(open ? "menu.close" : "menu.open"));
    };
    onLang(() => toggle.setAttribute("aria-label", t(menu.hidden ? "menu.open" : "menu.close")));

    toggle.addEventListener("click", () => setOpen(menu.hidden));
    menu.addEventListener("click", (e) => {
      if (e.target.closest("a")) setOpen(false);
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !menu.hidden) {
        setOpen(false);
        toggle.focus();
      }
    });
    window.matchMedia("(min-width: 1024px)").addEventListener("change", (e) => {
      if (e.matches) setOpen(false);
    });
  }

  /* ---------- Открывающие титры ---------- */
  function initIntro() {
    const root = document.documentElement;
    const intro = $("[data-intro]");
    if (!intro || !root.classList.contains("intro-pending")) return Promise.resolve();

    try { sessionStorage.setItem("kf-intro", "1"); } catch (err) { /* приватный режим */ }
    intro.hidden = false;
    root.classList.add("intro-lock");

    return new Promise((resolve) => {
      let opened = false;
      const open = () => {
        if (opened) return;
        opened = true;
        intro.classList.add("is-open");
        root.classList.remove("intro-lock", "intro-pending");
        resolve();
        setTimeout(() => intro.remove(), 1200);
      };
      requestAnimationFrame(() => intro.classList.add("is-playing"));
      setTimeout(open, 1350);
      intro.addEventListener("click", open);
      document.addEventListener("keydown", open, { once: true });
    });
  }

  /* ---------- Hero: дым и пушка (WebGL) ---------- */
  const VERT = `
    attribute vec2 aPos;
    void main() { gl_Position = vec4(aPos, 0.0, 1.0); }
  `;

  const FRAG = `
    #ifdef GL_FRAGMENT_PRECISION_HIGH
    precision highp float;
    #else
    precision mediump float;
    #endif
    uniform vec2 uRes;
    uniform float uTime;
    uniform vec2 uTarget;
    uniform vec2 uSource;
    uniform float uPower;

    float hash(vec2 p) {
      p = fract(p * vec2(123.34, 456.21));
      p += dot(p, p + 45.32);
      return fract(p.x * p.y);
    }

    float noise(vec2 p) {
      vec2 i = floor(p);
      vec2 f = fract(p);
      vec2 u = f * f * (3.0 - 2.0 * f);
      float a = hash(i);
      float b = hash(i + vec2(1.0, 0.0));
      float c = hash(i + vec2(0.0, 1.0));
      float d = hash(i + vec2(1.0, 1.0));
      return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    float fbm(vec2 p) {
      float v = 0.0;
      float a = 0.5;
      mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
      for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = m * p;
        a *= 0.5;
      }
      return v;
    }

    void main() {
      // Всё считаем в долях меньшей стороны: одинаково на телефоне и на мониторе
      float m = min(uRes.x, uRes.y);
      vec2 P = gl_FragCoord.xy / m;
      vec2 S = uSource / m;
      vec2 T = uTarget / m;
      float t = uTime * 0.05;

      // Дым: fbm с искажением области
      vec2 p = P * 1.7;
      vec2 q = vec2(fbm(p + vec2(0.0, -t)), fbm(p + vec2(5.2, 1.3) - t * 0.7));
      vec2 r = vec2(
        fbm(p + 2.2 * q + vec2(1.7, 9.2) + t * 0.9),
        fbm(p + 2.2 * q + vec2(8.3, 2.8) - t * 0.6)
      );
      float dens = smoothstep(0.3, 0.92, fbm(p + 1.9 * r));

      // Луч пушки: конус от прибора над кадром к точке под курсором
      vec2 D = T - S;
      float L = max(length(D), 0.001);
      vec2 dir = D / L;
      float along = dot(P - S, dir);
      float k = clamp(along / L, 0.0, 1.0);
      float off = length(P - (S + dir * along));
      float radius = mix(0.02, 0.17, k);
      float inBeam = step(0.0, along) * (1.0 - smoothstep(L * 0.95, L * 1.15, along));
      float core = (1.0 - smoothstep(radius * 0.5, radius, off)) * inBeam;
      float edge = exp(-off * off / (radius * radius * 2.6)) * inBeam;
      vec2 pd = P - T;
      float pool = exp(-dot(pd, pd) * 30.0);
      float beam = (core * 0.55 + edge * 0.3) * (0.45 + 0.55 * k);
      float lit = (beam + pool * 1.1) * uPower;
      float smoke = dens * lit;

      vec3 red = vec3(0.89, 0.16, 0.12);
      vec3 col = red * (smoke * 1.5 + lit * 0.09);
      // Пересвет в центре пятна уходит в тёплый белый, как на плёнке
      col += vec3(1.0, 0.62, 0.48) * pow(smoke, 3.2) * 0.6;
      col += vec3(dens) * 0.03;

      vec2 uv = gl_FragCoord.xy / uRes;
      vec2 vv = uv - 0.5;
      col *= 1.0 - dot(vv, vv) * 0.9;

      float g = hash(gl_FragCoord.xy + fract(uTime * 7.13) * 91.0) - 0.5;
      col += g * 0.03;

      gl_FragColor = vec4(col, 1.0);
    }
  `;

  function initHero(introReady) {
    const canvas = $("[data-haze]");
    if (!hero || !canvas) return;

    // Буквы заголовка раскаляются в пятне: координаты пятна в системе каждой строки
    const spans = $$("[data-hot] .line > span", hero);
    const heat = (clientX, clientY) => {
      spans.forEach((sp) => {
        const r = sp.getBoundingClientRect();
        sp.style.setProperty("--sx", `${(clientX - r.left).toFixed(1)}px`);
        sp.style.setProperty("--sy", `${(clientY - r.top).toFixed(1)}px`);
      });
    };
    hero.classList.add("has-spot");

    const gl = canvas.getContext("webgl", {
      alpha: false,
      antialias: false,
      depth: false,
      stencil: false,
      powerPreference: "low-power",
    });

    const program = gl && buildProgram(gl, VERT, FRAG);
    if (!program) {
      cssLamp(heat);
      introReady.then(() => setTimeout(lightOn, reduce ? 0 : 250));
      return;
    }

    gl.useProgram(program);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const aPos = gl.getAttribLocation(program, "aPos");
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

    const uRes = gl.getUniformLocation(program, "uRes");
    const uTime = gl.getUniformLocation(program, "uTime");
    const uTarget = gl.getUniformLocation(program, "uTarget");
    const uSource = gl.getUniformLocation(program, "uSource");
    const uPower = gl.getUniformLocation(program, "uPower");

    // Дым мягкий, поэтому рендерим в пониженном разрешении и растягиваем
    const density = Math.min(window.devicePixelRatio || 1, 2) * (finePointer ? 0.5 : 0.42);
    const firstRect = hero.getBoundingClientRect();
    let cssW = Math.max(1, firstRect.width);
    let cssH = Math.max(1, firstRect.height);

    // Пока зритель не взял пушку, оператор сам ведёт луч и иногда проходит по заголовку
    const drift = (t) => ({
      x: cssW * (0.5 + 0.28 * Math.sin(t * 0.17) + 0.07 * Math.sin(t * 0.61)),
      y: cssH * (0.42 + 0.16 * Math.sin(t * 0.23 + 1.1)),
    });

    let start = Infinity;
    const pos = drift(0);
    let target = { ...pos };
    let lastPointer = -Infinity;
    let lastFrame = performance.now();
    let running = false;
    let visible = true;
    let litFired = false;

    // Вспышка при включении: прибор «цепляется» не с первого раза
    const flicker = [[0, 0], [0.1, 0.65], [0.16, 0.05], [0.3, 0.9], [0.36, 0.25], [0.55, 1]];
    const power = (t) => {
      if (t < 0) return 0;
      if (reduce) return 1;
      for (let i = 1; i < flicker.length; i++) {
        const [t1, v1] = flicker[i];
        if (t <= t1) {
          const [t0, v0] = flicker[i - 1];
          return v0 + ((v1 - v0) * (t - t0)) / (t1 - t0);
        }
      }
      return 1;
    };

    function draw(now) {
      const t = reduce ? 18 : (now - start) / 1000;
      const dt = Math.min(0.1, (now - lastFrame) / 1000);
      lastFrame = now;

      if (!reduce && now - lastPointer > 3500) target = drift(Math.max(0, t));
      const k = reduce ? 1 : 1 - Math.exp(-dt * 4.2);
      pos.x += (target.x - pos.x) * k;
      pos.y += (target.y - pos.y) * k;

      const pw = power(t);
      gl.uniform2f(uRes, canvas.width, canvas.height);
      gl.uniform1f(uTime, Math.max(0, t));
      gl.uniform2f(uTarget, pos.x * density, (cssH - pos.y) * density);
      gl.uniform2f(uSource, cssW * (finePointer ? 0.82 : 0.76) * density, cssH * 1.06 * density);
      gl.uniform1f(uPower, pw);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

      const rect = hero.getBoundingClientRect();
      if (pw > 0.5) heat(rect.left + pos.x, rect.top + pos.y);
      else heat(-9999, -9999);

      if (!litFired && (reduce || t > 0.32)) {
        litFired = true;
        lightOn();
      }
    }

    const resize = () => {
      const rect = hero.getBoundingClientRect();
      cssW = Math.max(1, rect.width);
      cssH = Math.max(1, rect.height);
      canvas.width = Math.max(1, Math.round(cssW * density));
      canvas.height = Math.max(1, Math.round(cssH * density));
      gl.viewport(0, 0, canvas.width, canvas.height);
      if (!running) draw(performance.now());
    };

    // На телефонах хватает 30 кадров в секунду: дым медленный, а батарею жалко
    const frameGap = finePointer ? 0 : 1000 / 30 - 2;
    let lastDraw = 0;
    const loop = (now) => {
      if (!running) return;
      if (now - lastDraw >= frameGap) {
        lastDraw = now;
        draw(now);
      }
      requestAnimationFrame(loop);
    };

    const setRunning = () => {
      const should = !reduce && start !== Infinity && visible && !document.hidden;
      if (should && !running) {
        running = true;
        lastFrame = performance.now();
        requestAnimationFrame(loop);
      } else if (!should) {
        running = false;
      }
    };

    const aim = (e) => {
      const rect = hero.getBoundingClientRect();
      target = { x: e.clientX - rect.left, y: e.clientY - rect.top };
      lastPointer = performance.now();
      if (reduce) draw(lastPointer);
    };

    hero.addEventListener("pointermove", (e) => {
      if (e.pointerType !== "touch") aim(e);
    }, { passive: true });
    hero.addEventListener("pointerdown", aim, { passive: true });

    new ResizeObserver(resize).observe(hero);
    new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      setRunning();
    }).observe(hero);
    document.addEventListener("visibilitychange", setRunning);

    canvas.addEventListener("webglcontextlost", (e) => {
      e.preventDefault();
      running = false;
      cssLamp(heat);
    });

    resize();
    introReady.then(() => {
      start = performance.now();
      if (reduce) {
        draw(start);
        lightOn();
      }
      setRunning();
    });
  }

  function buildProgram(gl, vsSrc, fsSrc) {
    const compile = (type, src) => {
      const sh = gl.createShader(type);
      gl.shaderSource(sh, src);
      gl.compileShader(sh);
      if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
        console.warn(gl.getShaderInfoLog(sh));
        return null;
      }
      return sh;
    };
    const vs = compile(gl.VERTEX_SHADER, vsSrc);
    const fs = compile(gl.FRAGMENT_SHADER, fsSrc);
    if (!vs || !fs) return null;
    const prog = gl.createProgram();
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return null;
    return prog;
  }

  // Запасная пушка без WebGL: радиальный градиент за курсором
  function cssLamp(heat) {
    hero.classList.add("no-gl");
    if (!finePointer) return;
    let frame = 0;
    hero.addEventListener("pointermove", (e) => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        const rect = hero.getBoundingClientRect();
        hero.style.setProperty("--lx", `${((e.clientX - rect.left) / rect.width) * 100}%`);
        hero.style.setProperty("--ly", `${((e.clientY - rect.top) / rect.height) * 100}%`);
        heat(e.clientX, e.clientY);
      });
    }, { passive: true });
  }

  /* ---------- Манифест: слова загораются по мере прокрутки ---------- */
  function initManifest() {
    const sec = $("[data-manifest]");
    const text = $("[data-manifest-text]");
    if (!sec || !text || reduce) return;

    let words = [];
    let lit = -1;
    const split = () => {
      words = [];
      lit = -1;
      Array.from(text.childNodes).forEach((node) => {
        if (node.nodeType === Node.TEXT_NODE) {
          const frag = document.createDocumentFragment();
          node.textContent.split(/(\s+)/).forEach((part) => {
            if (!part) return;
            if (/^\s+$/.test(part)) {
              frag.append(part);
              return;
            }
            const w = document.createElement("span");
            w.className = "w";
            w.textContent = part;
            words.push(w);
            frag.append(w);
          });
          node.replaceWith(frag);
        } else if (node.nodeType === Node.ELEMENT_NODE) {
          node.classList.add("w", "key");
          words.push(node);
        }
      });
    };
    split();
    sec.classList.add("is-split");

    const refresh = addScene(text, (r, vh) => {
      const p = clamp((vh * 0.82 - r.top) / (r.height + vh * 0.3), 0, 1);
      const count = Math.round(p * words.length);
      if (count === lit) return;
      lit = count;
      words.forEach((w, i) => w.classList.toggle("on", i < count));
    });

    // Смена языка заменяет текст целиком: заново режем на слова и подсвечиваем
    onLang(() => {
      split();
      refresh();
    });
  }

  /* ---------- Шоурил: щель раскрывается, внутри идёт монтаж ---------- */
  function initReel() {
    const frame = $("[data-letterbox]");
    const screen = $("[data-reel-screen]");
    if (!frame || !screen) return;

    if (reduce) {
      frame.classList.add("is-scope");
      return;
    }

    let lastGate = -1;
    addScene(screen, (r, vh) => {
      const from = vh * 0.95;
      const to = Math.max((vh - r.height) / 2, 0);
      const p = clamp((from - r.top) / Math.max(1, from - to), 0, 1);
      const eased = 1 - Math.pow(1 - p, 3);
      const gate = Math.round((1 - eased) * 1000) / 1000;
      if (gate !== lastGate) {
        lastGate = gate;
        screen.style.setProperty("--gate", gate);
      }
      if (p > 0.97) frame.classList.add("is-scope");
    });

    // Монтаж: жёсткие склейки примерно раз в секунду, только пока кадр виден
    const shots = $$("[data-montage] img", screen);
    let idx = 0;
    let timer = 0;
    const cut = () => {
      shots[idx].classList.remove("is-on");
      idx = (idx + 1) % shots.length;
      shots[idx].classList.add("is-on");
    };
    if (shots.length > 1 && "IntersectionObserver" in window) {
      new IntersectionObserver(([entry]) => {
        clearInterval(timer);
        if (entry.isIntersecting) timer = setInterval(cut, 1150);
      }, { threshold: 0.2 }).observe(screen);
    }

    // Метка «Смотреть шоурил» идёт за курсором с небольшой инерцией
    const label = $("[data-reel-cursor]", screen);
    if (!label || !finePointer) return;
    let x = 0;
    let y = 0;
    let tx = 0;
    let ty = 0;
    let inside = false;
    let raf = 0;
    const step = () => {
      x += (tx - x) * 0.2;
      y += (ty - y) * 0.2;
      label.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0) translate(-50%, -50%)`;
      raf = inside || Math.abs(tx - x) + Math.abs(ty - y) > 0.5 ? requestAnimationFrame(step) : 0;
    };
    const local = (e) => {
      const r = screen.getBoundingClientRect();
      return [e.clientX - r.left, e.clientY - r.top];
    };
    screen.addEventListener("pointerenter", (e) => {
      [x, y] = local(e);
      [tx, ty] = [x, y];
      inside = true;
      label.classList.add("is-on");
      if (!raf) raf = requestAnimationFrame(step);
    });
    screen.addEventListener("pointermove", (e) => {
      [tx, ty] = local(e);
      if (!raf) raf = requestAnimationFrame(step);
    });
    screen.addEventListener("pointerleave", () => {
      inside = false;
      label.classList.remove("is-on");
    });
  }

  /* ---------- Работы: световой стол и плёнка, которая едет при прокрутке ---------- */
  function initPan() {
    const sec = $("[data-pan]");
    const pin = $("[data-pan-pin]");
    const track = $("[data-pan-track]");
    if (!sec || !pin || !track) return;
    const frames = $$(".frame", track);
    const titleEl = $("[data-pan-title]", sec);
    const metaEl = $("[data-pan-meta]", sec);

    // Стол включается, когда его верх доходит до середины экрана
    if ("IntersectionObserver" in window && !reduce) {
      const io = new IntersectionObserver(([entry]) => {
        if (!entry.isIntersecting) return;
        sec.classList.add("is-on");
        io.disconnect();
      }, { rootMargin: "0px 0px -45% 0px" });
      io.observe(sec);
    } else {
      sec.classList.add("is-on");
    }

    // Без закрепления (уменьшение движения): кадр отмечается, когда его долистали
    if (reduce || !("IntersectionObserver" in window)) {
      if (!("IntersectionObserver" in window)) return;
      const io = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          entry.target.classList.toggle("is-marked", entry.intersectionRatio >= 0.8);
        });
      }, { threshold: [0, 0.8, 1] });
      frames.forEach((f) => io.observe(f));
      return;
    }

    sec.classList.add("is-pinned");
    let distance = 0;
    let vw = 0;
    let centers = [];
    let current = -1;

    const setCurrent = (i) => {
      if (i === current) return;
      if (current >= 0) frames[current].classList.remove("is-marked");
      current = i;
      frames[i].classList.add("is-marked");
      label(i);
      if (titleEl) {
        titleEl.classList.remove("is-cut");
        void titleEl.offsetWidth;
        titleEl.classList.add("is-cut");
      }
    };
    const label = (i) => {
      const f = frames[i];
      if (titleEl) titleEl.textContent = $(".caption h3", f).textContent;
      if (metaEl) metaEl.textContent = $(".caption p", f).textContent;
    };
    onLang(() => label(Math.max(0, current)));

    let refresh = () => {};
    const measure = () => {
      vw = pin.clientWidth;
      distance = Math.max(0, track.scrollWidth - vw);
      centers = frames.map((f) => f.offsetLeft + f.offsetWidth / 2);
      sec.style.height = `${pin.offsetHeight + distance}px`;
      refresh();
    };

    refresh = addScene(sec, (r) => {
      const p = distance ? clamp(-r.top / distance, 0, 1) : 0;
      const x = p * distance;
      track.style.transform = `translate3d(${(-x).toFixed(1)}px, 0, 0) rotate(-1deg)`;
      track.style.transformOrigin = `${(x + vw / 2).toFixed(1)}px 50%`;
      let best = 0;
      let bestD = Infinity;
      centers.forEach((c, i) => {
        const d = Math.abs(c - x - vw / 2);
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      });
      setCurrent(best);
    });

    new ResizeObserver(measure).observe(pin);
    measure();

    // Клавиатура: фокус на кадре прокручивает страницу так, чтобы кадр встал в центр
    track.addEventListener("focusin", (e) => {
      const i = frames.indexOf(e.target.closest(".frame"));
      if (i < 0) return;
      const top = sec.getBoundingClientRect().top + window.scrollY;
      const x = clamp(centers[i] - vw / 2, 0, distance);
      window.scrollTo({ top: top + x, behavior: "instant" });
    });
  }

  /* ---------- Появление блоков ---------- */
  function initReveal() {
    const items = $$("[data-reveal]");
    if (!("IntersectionObserver" in window) || reduce) {
      items.forEach((el) => el.classList.add("is-in"));
      return;
    }
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-in");
        io.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -6% 0px", threshold: 0 });
    items.forEach((el) => io.observe(el));
  }

  /* ---------- Что снимаем: свет и кадр в красном за курсором ---------- */
  function initServices() {
    if (!finePointer) return;
    const rows = $$("[data-light]");
    rows.forEach((row) => {
      let frame = 0;
      row.addEventListener("pointermove", (e) => {
        if (frame) return;
        frame = requestAnimationFrame(() => {
          frame = 0;
          const rect = row.getBoundingClientRect();
          row.style.setProperty("--mx", `${((e.clientX - rect.left) / rect.width) * 100}%`);
        });
      }, { passive: true });
    });

    const list = $("[data-svc-list]");
    const preview = $("[data-svc-preview]");
    if (reduce || !list || !preview) return;
    const img = $("img", preview);
    let x = 0;
    let y = 0;
    let tx = 0;
    let ty = 0;
    let on = false;
    let raf = 0;

    // Кадр слегка заваливается в сторону движения, как карточка в руке
    const step = () => {
      const dx = (tx - x) * 0.14;
      x += dx;
      y += (ty - y) * 0.14;
      const tilt = clamp(dx * 0.35, -8, 8);
      preview.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0) translate(-50%, -55%) rotate(${tilt.toFixed(2)}deg)`;
      raf = on || Math.abs(dx) > 0.2 ? requestAnimationFrame(step) : 0;
    };
    const kick = () => {
      if (!raf) raf = requestAnimationFrame(step);
    };

    rows.forEach((row) => {
      row.addEventListener("pointerenter", (e) => {
        if (row.dataset.img && img.getAttribute("src") !== row.dataset.img) img.src = row.dataset.img;
        if (!on) {
          x = tx = e.clientX;
          y = ty = e.clientY;
        }
        on = true;
        preview.classList.add("is-on");
        kick();
      });
    });
    list.addEventListener("pointermove", (e) => {
      tx = e.clientX;
      ty = e.clientY;
      kick();
    }, { passive: true });
    list.addEventListener("pointerleave", () => {
      on = false;
      preview.classList.remove("is-on");
    });
  }

  /* ---------- Титры ---------- */
  function initRoll() {
    const roll = $("[data-roll]");
    const toggle = $("[data-roll-toggle]");
    if (!roll) return;
    const track = $(".roll-track", roll);

    // Постоянная скорость титров, сколько бы имён ни было
    // Титры стартуют уже на экране, а не с пустой шторки
    const setSpeed = () => {
      const pxPerSecond = 46;
      track.style.animationDuration = `${Math.max(12, track.scrollHeight / pxPerSecond)}s`;
      track.style.animationDelay = `${(-roll.clientHeight * 0.8) / pxPerSecond}s`;
    };
    setSpeed();
    new ResizeObserver(setSpeed).observe(track);

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(([entry]) => {
        roll.classList.toggle("is-offscreen", !entry.isIntersecting);
      }).observe(roll);
    }

    if (toggle) {
      const labelToggle = () => {
        toggle.textContent = t(roll.classList.contains("is-paused") ? "roll.start" : "roll.stop");
      };
      labelToggle();
      onLang(labelToggle);
      toggle.addEventListener("click", () => {
        const paused = roll.classList.toggle("is-paused");
        toggle.setAttribute("aria-pressed", String(paused));
        labelToggle();
      });
    }
  }

  /* ---------- Просмотр шоурила и проектов ---------- */
  function initViewer() {
    const dialog = $("[data-viewer]");
    if (!dialog) return;
    const media = $("[data-viewer-media]", dialog);
    const title = $("[data-viewer-title]", dialog);
    const meta = $("[data-viewer-meta]", dialog);
    const desc = $("[data-viewer-desc]", dialog);
    const reel = $("[data-reel]");

    const open = ({ heading, sub, text, video, img, note }) => {
      media.replaceChildren();
      const player = video ? embed(video, heading) : null;
      if (player) {
        media.append(player);
      } else if (img) {
        const pic = document.createElement("img");
        pic.src = img.currentSrc || img.src;
        pic.alt = img.alt;
        media.append(pic);
        if (note) media.append(note);
      }
      title.textContent = heading;
      meta.textContent = sub || "";
      desc.textContent = text || "";

      document.documentElement.style.overflow = "hidden";
      if (typeof dialog.showModal === "function") dialog.showModal();
      else dialog.setAttribute("open", "");
    };

    const close = () => {
      if (typeof dialog.close === "function") dialog.close();
      else dialog.removeAttribute("open");
    };

    dialog.addEventListener("close", () => {
      media.replaceChildren();
      document.documentElement.style.overflow = "";
    });
    dialog.addEventListener("click", (e) => {
      if (e.target === dialog || e.target.closest("[data-viewer-close]")) close();
      if (e.target.closest("[data-viewer-jump]")) close();
    });

    const openReel = () => {
      const note = document.createElement("p");
      note.className = "viewer-note";
      note.innerHTML = t("reel.note");
      open({
        heading: t("reel.title"),
        sub: "KAGANFILM",
        video: reel ? reel.dataset.video : "",
        img: reel ? $("img", reel) : null,
        note,
      });
    };

    $$("[data-open-reel]").forEach((btn) => btn.addEventListener("click", (e) => {
      e.stopPropagation();
      openReel();
    }));
    if (reel) reel.addEventListener("click", openReel);

    $$("[data-project]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const frame = btn.closest(".frame");
        open({
          heading: $(".caption h3", frame).textContent.trim(),
          sub: $(".caption p", frame).textContent.trim(),
          text: btn.dataset.desc,
          video: btn.dataset.video,
          img: $("img", btn),
        });
      });
    });
  }

  // YouTube, Vimeo, RuTube, VK Видео или прямой файл
  function embed(url, label) {
    let m;
    let src = "";
    if ((m = url.match(/(?:youtube\.com\/(?:watch\?v=|embed\/|shorts\/)|youtu\.be\/)([\w-]{6,})/))) {
      src = `https://www.youtube-nocookie.com/embed/${m[1]}?autoplay=1&rel=0`;
    } else if ((m = url.match(/vimeo\.com\/(?:video\/)?(\d+)/))) {
      src = `https://player.vimeo.com/video/${m[1]}?autoplay=1&dnt=1`;
    } else if ((m = url.match(/rutube\.ru\/(?:video|play\/embed)\/([\w]+)/))) {
      src = `https://rutube.ru/play/embed/${m[1]}`;
    } else if ((m = url.match(/vk(?:video)?\.(?:com|ru)\/video(-?\d+)_(\d+)/))) {
      src = `https://vk.com/video_ext.php?oid=${m[1]}&id=${m[2]}&hd=2&autoplay=1`;
    } else if (/\.(mp4|webm|mov)(\?|$)/i.test(url)) {
      const v = document.createElement("video");
      v.src = url;
      v.controls = true;
      v.autoplay = true;
      v.playsInline = true;
      return v;
    }
    if (!src) return null;
    const frame = document.createElement("iframe");
    frame.src = src;
    frame.title = label;
    frame.allow = "autoplay; fullscreen; picture-in-picture; encrypted-media";
    frame.allowFullscreen = true;
    return frame;
  }

  /* ---------- Хлопушка ---------- */
  function initSlate() {
    const form = $("[data-slate]");
    if (!form) return;

    const submit = $("[data-submit]", form);
    const status = $("[data-status]", form);
    const takeEl = $("[data-take]", form);
    const dateEl = $("[data-date]", form);
    const done = $("[data-done]", form);
    const doneText = $("[data-done-text]", form);
    const again = $("[data-again]", form);
    const mailto = form.dataset.mailto || "";
    let take = 1;

    if (dateEl) {
      dateEl.textContent = new Intl.DateTimeFormat("ru-RU", {
        day: "2-digit",
        month: "2-digit",
        year: "2-digit",
      }).format(new Date());
    }

    const rules = {
      project: (v) => (v ? "" : "err.project"),
      name: (v) => (v ? "" : "err.name"),
      contact: (v) => {
        if (!v) return "err.contact";
        const email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
        const phone = v.replace(/\D/g, "").length >= 7;
        const tg = /^@?[a-zA-Z0-9_]{4,}$/.test(v);
        return email || phone || tg ? "" : "err.contactBad";
      },
    };

    // Ошибка хранится ключом, чтобы при смене языка перевести и её
    const setError = (input, key) => {
      const field = input.closest(".field");
      const err = $(".field-error", field);
      field.classList.toggle("is-invalid", Boolean(key));
      input.setAttribute("aria-invalid", key ? "true" : "false");
      input.dataset.err = key || "";
      if (err) err.textContent = key ? t(key) : "";
    };

    const validate = () => {
      let first = null;
      Object.entries(rules).forEach(([name, rule]) => {
        const input = form.elements[name];
        const message = rule(input.value.trim());
        setError(input, message);
        if (message && !first) first = input;
      });
      return first;
    };

    Object.keys(rules).forEach((name) => {
      form.elements[name].addEventListener("input", (e) => {
        if (e.target.closest(".field").classList.contains("is-invalid")) {
          setError(e.target, rules[name](e.target.value.trim()));
        }
      });
    });

    // Хлопок: палка падает, в момент удара короткая вспышка, как метка синхронизации
    const flash = $("[data-flash]");
    const clap = () => new Promise((resolve) => {
      form.classList.remove("is-clap");
      void form.offsetWidth;
      form.classList.add("is-clap");
      if (flash && !reduce) {
        setTimeout(() => {
          flash.classList.remove("is-on");
          void flash.offsetWidth;
          flash.classList.add("is-on");
        }, 130);
      }
      setTimeout(resolve, reduce ? 0 : 480);
    });

    const finish = (html) => {
      if (html) doneText.innerHTML = html;
      form.classList.add("is-done");
      done.hidden = false;
      done.focus();
    };

    const failText = () => {
      status.innerHTML = mailto ? t("send.fail", { mail: mailLink(mailto) }) : t("send.failNoMail");
    };
    const fail = () => {
      form.classList.remove("is-clap");
      status.classList.add("is-error");
      failText();
    };

    onLang(() => {
      Object.keys(rules).forEach((name) => {
        const input = form.elements[name];
        if (input.dataset.err) setError(input, input.dataset.err);
      });
      if (status.classList.contains("is-error")) failText();
    });

    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      take += 1;
      if (takeEl) takeEl.textContent = String(take);
      status.textContent = "";
      status.classList.remove("is-error");

      const invalid = validate();
      if (invalid) {
        invalid.focus();
        return;
      }

      await clap();
      const data = new FormData(form);
      const endpoint = form.dataset.endpoint;

      if (endpoint) {
        submit.disabled = true;
        submit.textContent = t("send.sending");
        try {
          const res = await fetch(endpoint, {
            method: "POST",
            body: data,
            headers: { Accept: "application/json" },
          });
          if (!res.ok) throw new Error(String(res.status));
          finish();
        } catch (err) {
          fail();
        } finally {
          submit.disabled = false;
          submit.textContent = t("slate.go");
        }
        return;
      }

      // Без сервера: письмо с заполненной заявкой в почтовом клиенте
      const lines = [
        `Проект: ${data.get("project")}`,
        `Заказчик: ${data.get("name")}`,
        `Связь: ${data.get("contact")}`,
        `Сроки: ${data.get("dates") || "не указаны"}`,
        `Бюджет: ${data.get("budget")}`,
        "",
        String(data.get("brief") || ""),
      ];
      const subject = `Заявка с сайта: ${data.get("project")}`;
      window.location.href = `mailto:${mailto}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(lines.join("\n"))}`;
      finish(t("send.mailto", { mail: mailLink(mailto) }));
    });

    again.addEventListener("click", () => {
      form.reset();
      form.classList.remove("is-done", "is-clap");
      done.hidden = true;
      form.elements.project.focus();
    });
  }

  /* ---------- Футер: прибор над логотипом ---------- */
  function initFooter() {
    const footer = $("[data-light-footer]");
    const mark = footer && $(".footer-mark", footer);
    if (!mark || !finePointer) return;
    let frame = 0;
    footer.addEventListener("pointermove", (e) => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        const rect = mark.getBoundingClientRect();
        mark.style.setProperty("--fx", `${((e.clientX - rect.left) / rect.width) * 100}%`);
        mark.style.setProperty("--fy", `${((e.clientY - rect.top) / rect.height) * 100}%`);
      });
    }, { passive: true });
  }

  safe(initLang);
  const introReady = safe(initIntro) || Promise.resolve();
  safe(initNav);
  safe(initMenu);
  safe(initHero, introReady);
  safe(initManifest);
  safe(initReel);
  safe(initPan);
  safe(initReveal);
  safe(initServices);
  safe(initRoll);
  safe(initViewer);
  safe(initSlate);
  safe(initFooter);

  // Страховка: титр hero появится, даже если с WebGL что-то пошло не так
  introReady.then(() => setTimeout(lightOn, 1600));
  setTimeout(lightOn, 4500);
})();
