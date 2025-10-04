(function () {
  const form = document.getElementById("slide-form");
  const feedback = form?.querySelector(".form-feedback");
  const list = document.getElementById("slides-list");

  if (!form || !list) return;

  async function refreshSlides() {
    const response = await fetch("/api/slides");
    if (!response.ok) return;
    const data = await response.json();
    renderList(data.slides || []);
  }

  function renderList(slides) {
    list.innerHTML = "";

    if (!slides.length) {
      const item = document.createElement("li");
      item.textContent = "Keine Folien vorhanden. Lege die erste Folie an.";
      list.appendChild(item);
      return;
    }

    slides.forEach((slide, index) => {
      const item = document.createElement("li");
      item.dataset.index = String(index);
      item.innerHTML = `
        <div class="slide-card">
          <strong>${slide.title}</strong>
          <p>${slide.description ?? ""}</p>
          <span class="url">${slide.image_url}</span>
          <div class="card-actions">
            <button data-action="edit">Bearbeiten</button>
            <button data-action="delete" class="danger">Löschen</button>
          </div>
        </div>`;
      list.appendChild(item);
    });
  }

  async function createSlide(payload) {
    const response = await fetch("/api/slides", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      throw new Error(error.error || "Speichern fehlgeschlagen");
    }
    return response.json();
  }

  async function updateSlide(index, payload) {
    const response = await fetch(`/api/slides/${index}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      throw new Error(error.error || "Aktualisierung fehlgeschlagen");
    }
    return response.json();
  }

  async function deleteSlide(index) {
    const response = await fetch(`/api/slides/${index}`, { method: "DELETE" });
    if (!response.ok) {
      const error = await response.json().catch(() => ({}));
      throw new Error(error.error || "Löschen fehlgeschlagen");
    }
    return response.json();
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const formData = new FormData(form);
    const payload = Object.fromEntries(formData.entries());

    try {
      const result = await createSlide(payload);
      if (feedback) {
        feedback.hidden = false;
        feedback.textContent = "Folie gespeichert";
      }
      form.reset();
      renderList(result.slides || []);
    } catch (error) {
      if (feedback) {
        feedback.hidden = false;
        feedback.textContent = error.message;
      }
    }
  });

  list.addEventListener("click", async (event) => {
    const target = event.target;
    if (!(target instanceof HTMLElement)) return;

    const action = target.dataset.action;
    if (!action) return;

    const listItem = target.closest("li");
    if (!listItem) return;

    const index = Number.parseInt(listItem.dataset.index ?? "-1", 10);
    if (Number.isNaN(index) || index < 0) return;

    if (action === "delete") {
      try {
        const result = await deleteSlide(index);
        renderList(result.slides || []);
      } catch (error) {
        alert(error.message);
      }
      return;
    }

    if (action === "edit") {
      const title = prompt("Neuer Titel", listItem.querySelector("strong")?.textContent ?? "");
      if (title === null) return;
      const description = prompt(
        "Neue Beschreibung",
        listItem.querySelector("p")?.textContent ?? ""
      );
      if (description === null) return;
      const imageUrl = prompt(
        "Neue Bild-URL",
        listItem.querySelector(".url")?.textContent ?? ""
      );
      if (imageUrl === null) return;

      try {
        const result = await updateSlide(index, {
          title,
          description,
          image_url: imageUrl,
        });
        renderList(result.slides || []);
      } catch (error) {
        alert(error.message);
      }
    }
  });
})();
