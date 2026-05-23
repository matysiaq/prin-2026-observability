# Wymagania wstępne — Konfiguracja klastra Kubernetes na GCP

Przed pierwszymi zajęciami musisz mieć działający klaster Kubernetes na Google Cloud Platform.
Wykonuj kroki po kolei. Jeśli coś się nie powiedzie, zatrzymaj się i poproś o pomoc.

Szacowany czas: **30–45 minut**

---

## Krok 1 — Utwórz konto Google Cloud

Google Cloud oferuje **bezpłatny okres próbny z $300 kredytów** ważnych przez 90 dni.

> **Zanim zaczniesz:** Bezpłatny okres próbny obejmuje $300 kredytów ważnych przez 90 dni — w tym czasie nie są naliczane żadne opłaty. Jeśli nie jesteś pewien, czy Twoje konto kwalifikuje się do okresu próbnego, sprawdź [console.cloud.google.com/billing](https://console.cloud.google.com/billing) lub zapytaj prowadzącego.

1. Przejdź na [cloud.google.com](https://cloud.google.com) i kliknij **Get started for free**.
2. Zaloguj się na swoje konto Google.
3. Wypełnij formularz rejestracyjny. Google wymaga podania **karty kredytowej** w celu weryfikacji tożsamości.
4. Po aktywacji zostaniesz przekierowany do **Google Cloud Console** pod adresem [console.cloud.google.com](https://console.cloud.google.com).

---

## Krok 2 — Zapisz swoje Project ID

Google Cloud automatycznie tworzy dla Ciebie domyślny projekt.

1. W Cloud Console spójrz na górny pasek — obok logo Google Cloud widoczna jest nazwa projektu.
2. Kliknij nazwę projektu, aby otworzyć selektor projektów.
3. Skopiuj **Project ID** — wygląda on podobnie do: `my-project-123456`

> **Project ID** różni się od **Project Name**. Potrzebujesz identyfikatora (małe litery, może zawierać cyfry).

Będziesz go potrzebować w Kroku 6.

---

## Krok 3 — Otwórz Google Cloud Shell

Cloud Shell to terminal działający w przeglądarce, z wszystkimi potrzebnymi narzędziami zainstalowanymi fabrycznie (gcloud, kubectl, terraform). Nie jest wymagana żadna instalacja lokalna.

1. W Cloud Console kliknij **ikonę terminala** (`>_`) w prawym górnym rogu.
2. Na dole strony otworzy się panel terminala.
3. Poczekaj kilka sekund na uruchomienie powłoki.

> Wszystkie kolejne kroki wykonujesz wewnątrz Cloud Shell.

---

## Krok 4 — Wygeneruj parę kluczy SSH

Maszyny wirtualne klastra wymagają klucza SSH do konfiguracji.

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

Sprawdź, czy klucze zostały utworzone:

```bash
ls ~/.ssh/id_rsa ~/.ssh/id_rsa.pub
```

---

## Krok 5 — Pobierz skrypty warsztatowe

```bash
cd ~
git clone https://github.com/matysiaq/prin-2026-observability.git
cd prin-2026-observability/scripts/gcp-scripts
```

---

## Krok 6 — Skonfiguruj klaster

Otwórz plik konfiguracyjny w dowolnym edytorze:

```bash
vim config.yaml      # naciśnij i aby wejść w tryb wstawiania, Esc a następnie :wq aby zapisać i wyjść
nano config.yaml     # Ctrl+X, potem Y, potem Enter aby zapisać i wyjść
```

Znajdź linię:

```yaml
  project: "TODO: your-project-id"
```

Zastąp ją swoim Project ID z Kroku 2, na przykład:

```yaml
  project: "my-project-123456"
```

Reszty pliku nie musisz zmieniać.

---

## Krok 7 — Wdróż klaster

Nadaj skryptowi uprawnienia do uruchomienia i wykonaj go:

```bash
chmod +x deploy.sh
./deploy.sh
```

Skrypt wykona kolejno:
1. Instalację Ansible (niedostępne domyślnie w Cloud Shell — zajmuje ~1 minutę)
2. Aktywację Compute Engine API dla Twojego projektu
3. Utworzenie 1 maszyny wirtualnej na GCP za pomocą Terraform (~3 minuty)
4. Konfigurację Kubernetes na maszynie za pomocą Ansible (~10 minut)

Łączny czas oczekiwania: około **15 minut**.

Postęp będzie widoczny jako komunikaty zaczynające się od `==>`. Nie zamykaj Cloud Shell w tym czasie.

---

## Krok 8 — Zweryfikuj klaster

Po zakończeniu skryptu zobaczysz komunikat:

```
============================================================
  Cluster 'k8s-workshop' is ready!
  Mode:       3-node (1 master + 2 workers, e2-standard-2)
  Kubeconfig: /home/.../kubeconfigs/k8s-workshop.config
============================================================
```

Wskaż `kubectl` na nowy klaster:

```bash
export KUBECONFIG=~/prin-2026-observability/scripts/gcp-scripts/ansible/kubeconfigs/k8s-workshop.config
```

Sprawdź, czy węzeł ma status `Ready`:

```bash
kubectl get nodes
```

Oczekiwany wynik (może zająć do 2 minut — węzły robocze mogą chwilowo pokazywać `NotReady` podczas inicjalizacji Cilium CNI):

```
NAME                    STATUS   ROLES           AGE   VERSION
k8s-workshop-master     Ready    control-plane   5m    v1.30.0
k8s-workshop-worker-1   Ready    <none>          4m    v1.30.0
k8s-workshop-worker-2   Ready    <none>          4m    v1.30.0
```

---

## Krok 9 — Dodaj KUBECONFIG do profilu powłoki (zalecane)

Dzięki temu nie będziesz musiał ponownie ustawiać KUBECONFIG przy każdym otwarciu Cloud Shell:

```bash
echo 'export KUBECONFIG=~/prin-2026-observability/scripts/gcp-scripts/ansible/kubeconfigs/k8s-workshop.config' >> ~/.bashrc
source ~/.bashrc
```

---

## Krok 10 — Skopiuj Kubeconfig na swój komputer (opcjonalne)

Jeśli chcesz używać `kubectl` z własnego laptopa zamiast Cloud Shell, musisz skopiować plik kubeconfig lokalnie. Na Twoim komputerze musi być zainstalowany `kubectl`.

**W Cloud Shell** wyświetl zawartość pliku kubeconfig:

```bash
cat ~/prin-2026-observability/scripts/gcp-scripts/ansible/kubeconfigs/k8s-workshop.config
```

**Na swoim komputerze** utwórz plik i wklej zawartość:

```bash
# Linux / macOS
mkdir -p ~/.kube
nano ~/.kube/k8s-workshop.config   # wklej zawartość i zapisz
export KUBECONFIG=~/.kube/k8s-workshop.config
```

```powershell
# Windows (PowerShell)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.kube"
notepad "$env:USERPROFILE\.kube\k8s-workshop.config"   # wklej zawartość i zapisz
$env:KUBECONFIG = "$env:USERPROFILE\.kube\k8s-workshop.config"
```

Sprawdź, czy połączenie działa:

```bash
kubectl get nodes
```

> Plik kubeconfig zawiera już zewnętrzny adres IP klastra, więc działa z dowolnej sieci bez żadnych modyfikacji.

---

## Przypomnienie o kosztach

Klaster kosztuje około **$0,20/godzinę** podczas działania (3 × e2-standard-2 w regionie europe-central2).
Gdy nie pracujesz, zatrzymaj maszyny wirtualne, aby oszczędzić kredyty:

```bash
# Zatrzymaj wszystkie węzły (statyczne adresy IP są zachowane)
gcloud compute instances stop k8s-workshop-master k8s-workshop-worker-1 k8s-workshop-worker-2 --zone europe-central2-a

# Uruchom je ponownie
gcloud compute instances start k8s-workshop-master k8s-workshop-worker-1 k8s-workshop-worker-2 --zone europe-central2-a
```

> Statyczne adresy IP **nie zmieniają się** po zatrzymaniu i ponownym uruchomieniu maszyn. Twoje połączenie `kubectl` nadal będzie działać po restarcie.

> **Uwaga:** Po uruchomieniu maszyn poczekaj około 2 minut, aż wszystkie węzły osiągną status `Ready`.

---

## Czyszczenie po zajęciach

Aby usunąć wszystkie zasoby i zatrzymać naliczanie opłat:

```bash
cd ~/prin-2026-observability/scripts/gcp-scripts/terraform
terraform destroy -auto-approve
```

---

## Rozwiązywanie problemów

| Problem | Rozwiązanie |
|---------|-------------|
| `ERROR: SSH public key not found` | Powtórz Krok 4 |
| `ERROR: Please set your GCP project ID` | Edytuj config.yaml i uzupełnij pole `gcp.project` |
| `kubectl: connection refused` | Poczekaj jeszcze 2 minuty — serwer API może jeszcze się uruchamiać |
| Węzeł utknął w stanie `NotReady` | Uruchom `kubectl describe node <nazwa>` i pokaż wynik prowadzącemu |
| Cloud Shell rozłączył się w trakcie wdrożenia | Otwórz Cloud Shell ponownie i uruchom `./deploy.sh --skip-terraform` |
| GCP ponownie prosi o kartę kredytową | Twój okres próbny mógł się nie aktywować — sprawdź [console.cloud.google.com/billing](https://console.cloud.google.com/billing) |
| `PERMISSION_DENIED: Compute Engine API not enabled` | Uruchom: `gcloud services enable compute.googleapis.com --project=TWOJE_PROJECT_ID` |
