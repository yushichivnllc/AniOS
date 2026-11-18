/* AniOS — tương tác nhỏ, không phụ thuộc thư viện.
   Nguyên tắc: trang vẫn đọc được đầy đủ khi JavaScript tắt; mọi hiệu ứng đều
   tôn trọng prefers-reduced-motion. */
(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- Menu trên điện thoại ---------- */
  const toggle = document.getElementById("navToggle");
  const links = document.getElementById("navLinks");

  if (toggle && links) {
    const setOpen = (open) => {
      links.classList.toggle("is-open", open);
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? "Đóng menu" : "Mở menu");
    };

    toggle.addEventListener("click", () => {
      setOpen(toggle.getAttribute("aria-expanded") !== "true");
    });

    links.addEventListener("click", (event) => {
      if (event.target.closest("a")) setOpen(false);
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") setOpen(false);
    });
  }

  /* ---------- Hiện dần khi cuộn ---------- */
  const revealables = document.querySelectorAll("[data-reveal]");

  if (revealables.length) {
    if (reduceMotion || !("IntersectionObserver" in window)) {
      revealables.forEach((el) => el.classList.add("is-in"));
    } else {
      const observer = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (!entry.isIntersecting) return;
            const el = entry.target;
            const delay = Number(el.dataset.revealDelay || 0);
            window.setTimeout(() => el.classList.add("is-in"), delay);
            observer.unobserve(el);
          });
        },
        { rootMargin: "0px 0px -12% 0px", threshold: 0.12 }
      );

      revealables.forEach((el, index) => {
        // Lệch nhịp một chút để các thẻ trong cùng hàng không bật lên cùng lúc.
        el.dataset.revealDelay = String((index % 4) * 70);
        observer.observe(el);
      });
    }
  }

  /* ---------- Thị sai nhẹ cho cụm ảnh dán ở hero ---------- */
  const stage = document.querySelector(".hero__art");
  const layers = document.querySelectorAll("[data-parallax]");

  if (stage && layers.length && !reduceMotion) {
    let frame = 0;
    let pointerX = 0;
    let pointerY = 0;

    const apply = () => {
      frame = 0;
      const depth = (el) => Number(el.dataset.parallax || 0.05);
      layers.forEach((el) => {
        const d = depth(el);
        el.style.setProperty("translate", `${pointerX * d * 60}px ${pointerY * d * 60}px`);
      });
    };

    stage.addEventListener("pointermove", (event) => {
      if (event.pointerType === "touch") return;
      const rect = stage.getBoundingClientRect();
      pointerX = (event.clientX - rect.left) / rect.width - 0.5;
      pointerY = (event.clientY - rect.top) / rect.height - 0.5;
      if (!frame) frame = window.requestAnimationFrame(apply);
    });

    stage.addEventListener("pointerleave", () => {
      pointerX = 0;
      pointerY = 0;
      if (!frame) frame = window.requestAnimationFrame(apply);
    });
  }

  /* ---------- Mục lục: đánh dấu mục đang xem ---------- */
  const sections = [...document.querySelectorAll("main section[id]")];
  const navAnchors = [...document.querySelectorAll(".nav__links a")];

  if (sections.length && navAnchors.length && "IntersectionObserver" in window) {
    const byId = new Map(
      navAnchors.map((a) => [a.getAttribute("href")?.replace("#", ""), a])
    );

    const spy = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          const anchor = byId.get(entry.target.id);
          if (!anchor) return;
          if (entry.isIntersecting) {
            navAnchors.forEach((a) => a.removeAttribute("aria-current"));
            anchor.setAttribute("aria-current", "true");
          }
        });
      },
      { rootMargin: "-45% 0px -45% 0px" }
    );

    sections.forEach((section) => spy.observe(section));
  }
})();
