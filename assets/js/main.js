/* KAGANFILM: поведение страницы. Без зависимостей и без обработчиков scroll. */
(() => {
  "use strict";

  document.documentElement.classList.add("js");

  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(hover: hover) and (pointer: fine)").matches;

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  // Одна сломанная часть не должна гасить остальные
  const safe = (fn) => {
    try { fn(); } catch (err) { console.error(err); }
  };

  const hero = $("[data-hero]");
  const lightOn = () => hero && hero.classList.add("is-lit");

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
      toggle.setAttribute("aria-label", open ? "Закрыть меню" : "Открыть меню");
    };

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

  /* ---------- Hero: дым и красный прибор (WebGL) ---------- */
  const VERT = `
    attribute vec2 aPos;
    void main() { gl_Position = vec4(aPos, 0.0, 1.0); }
  `;

  const FRAG = `
    precision mediump float;
    uniform vec2 uRes;
    uniform float uTime;
    uniform vec2 uLight;
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
      vec2 uv = gl_FragCoord.xy / uRes;
      float asp = uRes.x / uRes.y;
      // Размер клубов привязан к меньшей стороне, чтобы на телефоне дым был таким же плотным
      vec2 p = gl_FragCoord.xy / min(uRes.x, uRes.y) * 1.7;
      float t = uTime * 0.05;

      // Дым: fbm с искажением области, медленно тянется вверх и вбок
      vec2 q = vec2(fbm(p + vec2(0.0, -t)), fbm(p + vec2(5.2, 1.3) - t * 0.7));
      vec2 r = vec2(
        fbm(p + 2.2 * q + vec2(1.7, 9.2) + t * 0.9),
        fbm(p + 2.2 * q + vec2(8.3, 2.8) - t * 0.6)
      );
      float d = fbm(p + 1.9 * r);
      d = smoothstep(0.3, 0.92, d);

      // Прибор
      vec2 lp = uLight / uRes;
      vec2 dv = vec2((uv.x - lp.x) * asp, uv.y - lp.y);
      float dist2 = dot(dv, dv);
      float core = exp(-dist2 * 10.0);
      float halo = 1.0 / (1.0 + dist2 * 22.0);
      float lit = (core * 1.35 + halo * 0.3) * uPower;
      float smoke = d * lit;

      vec3 red = vec3(0.89, 0.16, 0.12);
      // Немного света рассеивается в самом воздухе, даже где дым редкий
      vec3 col = red * (smoke * 1.5 + lit * 0.07);
      // Пересвет в центре пятна уходит в тёплый белый, как на плёнке
      col += vec3(1.0, 0.62, 0.48) * pow(smoke, 3.2) * 0.6;
      // Едва заметный дым вне пятна
      col += vec3(d) * 0.03;

      vec2 vv = uv - 0.5;
      col *= 1.0 - dot(vv, vv) * 0.9;

      float g = hash(gl_FragCoord.xy + fract(uTime * 7.13) * 91.0) - 0.5;
      col += g * 0.03;

      gl_FragColor = vec4(col, 1.0);
    }
  `;

  function initHero() {
    const canvas = $("[data-haze]");
    if (!hero || !canvas) return;

    const gl = canvas.getContext("webgl", {
      alpha: false,
      antialias: false,
      depth: false,
      stencil: false,
      powerPreference: "low-power",
    });

    const program = gl && buildProgram(gl, VERT, FRAG);
    if (!program) {
      cssLamp();
      setTimeout(lightOn, reduce ? 0 : 250);
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
    const uLight = gl.getUniformLocation(program, "uLight");
    const uPower = gl.getUniformLocation(program, "uPower");

    // Дым мягкий, поэтому рендерим в пониженном разрешении и растягиваем
    const density = Math.min(window.devicePixelRatio || 1, 2) * (finePointer ? 0.5 : 0.42);
    const firstRect = hero.getBoundingClientRect();
    let cssW = Math.max(1, firstRect.width);
    let cssH = Math.max(1, firstRect.height);

    const resize = () => {
      const rect = hero.getBoundingClientRect();
      cssW = Math.max(1, rect.width);
      cssH = Math.max(1, rect.height);
      canvas.width = Math.max(1, Math.round(cssW * density));
      canvas.height = Math.max(1, Math.round(cssH * density));
      gl.viewport(0, 0, canvas.width, canvas.height);
      if (!running) draw(performance.now());
    };

    // Пока зритель не взял прибор, он медленно ищет кадр сам
    const drift = (t) => ({
      x: cssW * (0.66 + 0.15 * Math.sin(t * 0.21)),
      y: cssH * (0.36 + 0.11 * Math.sin(t * 0.29 + 1.2)),
    });

    const start = performance.now();
    const pos = drift(0);
    let target = { ...pos };
    let lastPointer = -Infinity;
    let lastFrame = start;
    let running = false;
    let visible = true;
    let litFired = false;

    // Вспышка при включении: прибор «цепляется» не с первого раза
    const flicker = [[0, 0], [0.1, 0.65], [0.16, 0.05], [0.3, 0.9], [0.36, 0.25], [0.55, 1]];
    const power = (t) => {
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

      if (!reduce && now - lastPointer > 3500) target = drift(t);
      const k = reduce ? 1 : 1 - Math.exp(-dt * 4.2);
      pos.x += (target.x - pos.x) * k;
      pos.y += (target.y - pos.y) * k;

      gl.uniform2f(uRes, canvas.width, canvas.height);
      gl.uniform1f(uTime, t);
      gl.uniform2f(uLight, pos.x * density, (cssH - pos.y) * density);
      gl.uniform1f(uPower, power(t));
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

      if (!litFired && (reduce || t > 0.32)) {
        litFired = true;
        lightOn();
      }
    }

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
      const should = !reduce && visible && !document.hidden;
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
      cssLamp();
    });

    resize();
    setRunning();
    if (reduce) draw(performance.now());
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

  // Запасной прибор без WebGL: радиальный градиент за курсором
  function cssLamp() {
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
      });
    }, { passive: true });
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

  /* ---------- Шоурил: шторки синемаскопа ---------- */
  function initLetterbox() {
    const frame = $("[data-letterbox]");
    if (!frame) return;
    if (reduce || !("IntersectionObserver" in window)) {
      frame.classList.add("is-scope");
      return;
    }
    const io = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) return;
      frame.classList.add("is-scope");
      io.disconnect();
    }, { threshold: 0.55 });
    io.observe(frame);
  }

  /* ---------- Контактный лист ---------- */
  function initSheet() {
    const sheet = $("[data-sheet]");
    if (!sheet || !("IntersectionObserver" in window)) return;

    if (finePointer) {
      // На десктопе один кадр уже отмечен, остальные отмечаются наведением
      const featured = $(".frame[data-featured]", sheet);
      if (!featured) return;
      const io = new IntersectionObserver(([entry]) => {
        if (!entry.isIntersecting) return;
        setTimeout(() => featured.classList.add("is-marked"), reduce ? 0 : 650);
        io.disconnect();
      }, { threshold: 0.35 });
      io.observe(sheet);
      return;
    }

    // На телефоне кадр отмечается, когда его долистали до центра
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        entry.target.classList.toggle("is-marked", entry.intersectionRatio >= 0.8);
      });
    }, { threshold: [0, 0.8, 1] });
    $$(".frame", sheet).forEach((el) => io.observe(el));
  }

  /* ---------- Что снимаем: свет за курсором ---------- */
  function initServices() {
    if (!finePointer) return;
    $$("[data-light]").forEach((row) => {
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
      toggle.addEventListener("click", () => {
        const paused = roll.classList.toggle("is-paused");
        toggle.setAttribute("aria-pressed", String(paused));
        toggle.textContent = paused ? "Запустить титры" : "Остановить титры";
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
      note.innerHTML = 'Новый шоурил в монтаже. Пока можно посмотреть <a href="#work" data-viewer-jump>работы</a> на контактном листе.';
      open({
        heading: "Шоурил 2026",
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
      project: (v) => (v ? "" : "Напишите, что снимаем"),
      name: (v) => (v ? "" : "Как к вам обращаться?"),
      contact: (v) => {
        if (!v) return "Оставьте телефон, Telegram или почту";
        const email = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
        const phone = v.replace(/\D/g, "").length >= 7;
        const tg = /^@?[a-zA-Z0-9_]{4,}$/.test(v);
        return email || phone || tg ? "" : "Не похоже на телефон, Telegram или почту";
      },
    };

    const setError = (input, message) => {
      const field = input.closest(".field");
      const err = $(".field-error", field);
      field.classList.toggle("is-invalid", Boolean(message));
      input.setAttribute("aria-invalid", message ? "true" : "false");
      if (err) err.textContent = message;
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

    const clap = () => new Promise((resolve) => {
      form.classList.remove("is-clap");
      void form.offsetWidth;
      form.classList.add("is-clap");
      setTimeout(resolve, reduce ? 0 : 480);
    });

    const finish = (html) => {
      if (html) doneText.innerHTML = html;
      form.classList.add("is-done");
      done.hidden = false;
      done.focus();
    };

    const fail = () => {
      form.classList.remove("is-clap");
      status.classList.add("is-error");
      status.innerHTML = mailto
        ? `Не получилось отправить. Напишите нам на <a href="mailto:${mailto}">${mailto}</a>.`
        : "Не получилось отправить. Попробуйте ещё раз чуть позже.";
    };

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
        submit.textContent = "Отправляем";
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
          submit.textContent = "Мотор!";
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
      finish(`Открыли почту с готовым письмом. Если ничего не произошло, напишите на <a href="mailto:${mailto}">${mailto}</a>.`);
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

  safe(initNav);
  safe(initMenu);
  safe(initHero);
  safe(initReveal);
  safe(initLetterbox);
  safe(initSheet);
  safe(initServices);
  safe(initRoll);
  safe(initViewer);
  safe(initSlate);
  safe(initFooter);

  // Страховка: титр hero появится, даже если с WebGL что-то пошло не так
  setTimeout(lightOn, 1600);
})();
