import { createRoot } from "react-dom/client";

function App() {
  return <h1>{{cookiecutter.service_name}}</h1>;
}

createRoot(document.getElementById("root")!).render(<App />);
