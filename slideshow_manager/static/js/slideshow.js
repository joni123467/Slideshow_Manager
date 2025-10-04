(function () {
  const container = document.getElementById("slides-container");
  if (!container) return;

  const slides = Array.from(container.querySelectorAll(".slide"));
  if (!slides.length) return;

  let index = 0;
  const indicator = document.getElementById("slide-indicator");
  const prevButton = document.getElementById("prev-slide");
  const nextButton = document.getElementById("next-slide");

  function update(newIndex) {
    slides[index].classList.remove("is-active");
    index = (newIndex + slides.length) % slides.length;
    slides[index].classList.add("is-active");
    if (indicator) {
      indicator.textContent = `${index + 1} / ${slides.length}`;
    }
  }

  prevButton?.addEventListener("click", () => update(index - 1));
  nextButton?.addEventListener("click", () => update(index + 1));

  document.addEventListener("keydown", (event) => {
    if (event.key === "ArrowRight") {
      update(index + 1);
    } else if (event.key === "ArrowLeft") {
      update(index - 1);
    }
  });
})();
